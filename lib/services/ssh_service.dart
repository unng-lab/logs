import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:dartssh2/dartssh2.dart';
import 'package:meta/meta.dart';

import '../models/app_settings.dart';
import '../models/log_entry.dart';
import '../models/metrics.dart';
import '../models/server_config.dart';

/// Инкапсулирует работу по SSH: подключение, чтение логов и получение метрик.
class SSHConnectionException implements Exception {
  const SSHConnectionException._({
    required this.message,
    required this.host,
    required this.port,
    this.cause,
  });

  factory SSHConnectionException.timeout({
    required String host,
    required int port,
    Object? cause,
  }) {
    return SSHConnectionException._(
      message: 'Не удалось подключиться к $host:$port: истекло время ожидания.',
      host: host,
      port: port,
      cause: cause,
    );
  }

  factory SSHConnectionException.socket({
    required String host,
    required int port,
    required SocketException cause,
  }) {
    final description = cause.message.isNotEmpty
        ? cause.message
        : 'ошибка сокета (${cause.osError?.message ?? cause.toString()})';
    return SSHConnectionException._(
      message: 'Не удалось подключиться к $host:$port: $description.',
      host: host,
      port: port,
      cause: cause,
    );
  }

  final String message;
  final String host;
  final int port;
  final Object? cause;

  @override
  String toString() => message;
}

class SSHService {
  /// Устанавливает SSH-подключение с учётом пароля и ключей.
  Future<SSHClient> _connect(ServerConfig server) async {
    try {
      final socket = await SSHSocket.connect(
        server.host,
        server.port,
        timeout: const Duration(seconds: 12),
      );

      List<SSHKeyPair>? identity;
      if (server.privateKey != null && server.privateKey!.trim().isNotEmpty) {
        // Если указан приватный ключ, подготавливаем пару ключей для аутентификации.
        identity = SSHKeyPair.fromPem(
          server.privateKey!,
          server.passphrase ?? '',
        );
      }

      return SSHClient(
        socket,
        username: server.username,
        identities: identity,
        onPasswordRequest: () => server.password ?? '',
      );
    } on TimeoutException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        SSHConnectionException.timeout(
          host: server.host,
          port: server.port,
          cause: error,
        ),
        stackTrace,
      );
    } on Object catch (error, stackTrace) {
      if (error is SocketException) {
        Error.throwWithStackTrace(
          SSHConnectionException.socket(
            host: server.host,
            port: server.port,
            cause: error,
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Возвращает список активных systemd-сервисов на удалённом сервере.
  Future<List<String>> fetchServices(ServerConfig server) async {
    final client = await _connect(server);
    try {
      const command =
          "systemctl list-units --type=service --state=running --no-legend --no-pager | awk '{print \$1}'";
      final result = await _runCommand(client, command);
      final services = result
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      services.sort();
      return services;
    } finally {
      client.close();
    }
  }

  /// Создаёт поток логов journalctl для выбранных сервисов.
  Stream<LogEntry> streamLogs(
    ServerConfig server,
    List<String> services,
    AppSettings settings,
  ) {
    final controller = StreamController<LogEntry>.broadcast();
    SSHClient? client;
    SSHSession? channel;
    StreamSubscription<String>? subscription;
    final allowedServices = services.toSet();

    /// Закрывает все ассоциированные ресурсы соединения.
    Future<void> closeResources() async {
      await subscription?.cancel();
      channel?.close();
      client?.close();
    }

    controller.onListen = () async {
      if (allowedServices.isEmpty) {
        await controller.close();
        return;
      }
      try {
        // Подключаемся по SSH и формируем команду journalctl.
        client = await _connect(server);
        final lines = settings.initialLogLines.clamp(1, 1000).toInt();
        final serviceArgs = services.map((service) => '-u $service').join(' ');
        final command =
            'journalctl $serviceArgs -n $lines -o json --follow --no-pager';
        channel = await client!.execute(command);
        final stdout =
            utf8.decoder.bind(channel!.stdout).transform(const LineSplitter());
        subscription = stdout.listen(
          (line) {
            if (line.trim().isEmpty) {
              return;
            }
            try {
              final decoded = jsonDecode(line) as Map<String, dynamic>;
              final entry = _mapJsonToEntry(decoded, allowedServices);
              if (entry != null) {
                // Отправляем только те записи, которые относятся к выбранным сервисам.
                controller.add(entry);
              }
            } catch (_) {
              // Ignore invalid JSON lines.
            }
          },
          onError: controller.addError,
          onDone: () async {
            await closeResources();
            if (!controller.isClosed) {
              await controller.close();
            }
          },
          cancelOnError: false,
        );
      } on Object catch (error, stackTrace) {
        await closeResources();
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
          await controller.close();
        }
      }
    };

    controller.onCancel = () async {
      await closeResources();
      if (!controller.isClosed) {
        await controller.close();
      }
    };

    return controller.stream;
  }

  /// Проверяет, удаётся ли выполнить простую команду на сервере.
  Future<bool> checkConnection(ServerConfig server) async {
    SSHClient? client;
    try {
      client = await _connect(server);
      await _runCommand(client, 'true');
      return true;
    } catch (_) {
      return false;
    } finally {
      client?.close();
    }
  }

  /// Вычисляет среднюю скорость появления записей журнала за последнюю минуту.
  Future<double> fetchLogRate(ServerConfig server) async {
    SSHClient? client;
    try {
      client = await _connect(server);
      const command = 'journalctl --since "1 minute ago" --no-pager | wc -l';
      final rawOutput = await _runCommand(client, command);
      final trimmed = rawOutput.trim();
      if (trimmed.isEmpty) {
        return 0;
      }
      final tokens = trimmed.split(RegExp(r'\s+'));
      final count =
          int.tryParse(tokens.isNotEmpty ? tokens.last : trimmed) ?? 0;
      if (count <= 0) {
        return 0;
      }
      return count / 60.0;
    } finally {
      client?.close();
    }
  }

  /// Получает текущие метрики CPU и памяти всего сервера.
  Future<ServerMetrics> fetchServerMetrics(ServerConfig server) async {
    SSHClient? client;
    try {
      client = await _connect(server);
      final cpuOutput = await _runCommand(
        client,
        "LC_ALL=C top -bn1 | grep 'Cpu(s)' | head -n1",
      );
      final memoryOutput = await _runCommand(
        client,
        "LC_ALL=C free -b | awk '/Mem:/ {print \$2 " " \$3}'",
      );
      final cpuUsage = _parseCpuUsage(cpuOutput);
      final (memoryUsagePercent, memoryTotalBytes, memoryUsedBytes) =
          _parseMemoryUsage(memoryOutput);
      return ServerMetrics(
        cpuUsagePercent: cpuUsage,
        memoryUsagePercent: memoryUsagePercent,
        memoryTotalBytes: memoryTotalBytes,
        memoryUsedBytes: memoryUsedBytes,
      );
    } finally {
      client?.close();
    }
  }

  /// Возвращает метрики выбранного systemd-сервиса.
  Future<ServiceMetrics> fetchServiceMetrics(
    ServerConfig server,
    String service,
  ) async {
    SSHClient? client;
    try {
      client = await _connect(server);
      final pidOutput = await _runCommand(
        client,
        "systemctl show '$service' --property=MainPID --value",
      );
      final pid = int.tryParse(pidOutput.trim());
      if (pid == null || pid <= 0) {
        return ServiceMetrics(pid: pid);
      }
      final statsOutput = await _runCommand(
        client,
        'LC_ALL=C ps -p $pid -o %cpu= -o %mem= -o rss=',
      );
      final (cpuUsage, memoryUsage, rssBytes) = _parseProcessStats(statsOutput);
      return ServiceMetrics(
        cpuUsagePercent: cpuUsage,
        memoryUsagePercent: memoryUsage,
        memoryRssBytes: rssBytes,
        pid: pid,
      );
    } finally {
      client?.close();
    }
  }

  /// Выполняет произвольную команду на сервере и возвращает её stdout.
  Future<String> _runCommand(SSHClient client, String command) async {
    final result = await client.execute(command);
    final output = await utf8.decoder.bind(result.stdout).join();
    result.close();
    return output;
  }

  double? _parseCpuUsage(String output) {
    final normalized = output.replaceAll(',', '.').toLowerCase();
    final idleMatch =
        RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*%?\s*(id|idle)')
            .firstMatch(normalized);
    if (idleMatch != null) {
      final idle = double.tryParse(idleMatch.group(1)!);
      if (idle != null) {
        final usage = 100 - idle;
        return usage.clamp(0, 100);
      }
    }

    final matches = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*%?\s*([a-z]+)')
        .allMatches(normalized);
    if (matches.isEmpty) {
      return null;
    }

    double total = 0;
    for (final match in matches) {
      final label = match.group(2);
      if (label == null || label == 'id' || label == 'idle') {
        continue;
      }
      final value = double.tryParse(match.group(1)!);
      if (value != null) {
        total += value;
      }
    }

    if (total <= 0) {
      return null;
    }
    return total.clamp(0, 100);
  }

  (double?, int?, int?) _parseMemoryUsage(String output) {
    final tokens = output.trim().split(RegExp(r'\s+'));
    if (tokens.length < 2) {
      return (null, null, null);
    }
    final total = int.tryParse(tokens[0]);
    final used = int.tryParse(tokens[1]);
    if (total == null || total <= 0 || used == null || used < 0) {
      return (null, total, used);
    }
    final percent = (used / total) * 100;
    return (percent.clamp(0, 100), total, used);
  }

  (double?, double?, int?) _parseProcessStats(String output) {
    final tokens = output.trim().split(RegExp(r'\s+'));
    if (tokens.isEmpty) {
      return (null, null, null);
    }
    double? cpu;
    double? mem;
    int? rss;
    if (tokens.isNotEmpty) {
      cpu = double.tryParse(tokens[0].replaceAll(',', '.'));
    }
    if (tokens.length >= 2) {
      mem = double.tryParse(tokens[1].replaceAll(',', '.'));
    }
    if (tokens.length >= 3) {
      final rssValue = int.tryParse(tokens[2]);
      if (rssValue != null) {
        rss = rssValue * 1024; // rss reported в килобайтах
      }
    }
    return (cpu, mem, rss);
  }

  @visibleForTesting
  double? debugParseCpuUsage(String output) => _parseCpuUsage(output);

  /// Преобразует JSON-строку journalctl в доменную модель [LogEntry].
  LogEntry? _mapJsonToEntry(
    Map<String, dynamic> json,
    Set<String> allowedServices,
  ) {
    final message = (json['MESSAGE'] as String?) ?? '';
    final realtimeMicros = json['__REALTIME_TIMESTAMP']?.toString();
    final timestampMicros = int.tryParse(realtimeMicros ?? '');
    final timestamp = timestampMicros != null
        ? DateTime.fromMicrosecondsSinceEpoch(timestampMicros, isUtc: true)
        : DateTime.now().toUtc();
    final severity =
        LogEntry.severityFromPriority(json['PRIORITY']?.toString());
    final service = (json['_SYSTEMD_UNIT'] as String?) ??
        (json['SYSTEMD_UNIT'] as String?) ??
        (json['UNIT'] as String?) ??
        (json['SYSLOG_IDENTIFIER'] as String?);
    if (service == null ||
        service.isEmpty ||
        !allowedServices.contains(service)) {
      return null;
    }
    return LogEntry(
      timestamp: timestamp,
      message: message,
      severity: severity,
      service: service,
      raw: json,
      realtimeTimestampMicros: realtimeMicros,
      receivedAt: DateTime.now().toUtc(),
    );
  }
}
