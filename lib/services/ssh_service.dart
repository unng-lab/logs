import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../models/app_settings.dart';
import '../models/log_entry.dart';
import '../models/server_config.dart';

/// Инкапсулирует работу по SSH: подключение, чтение логов и получение метрик.
class SSHService {
  /// Устанавливает SSH-подключение с учётом пароля и ключей.
  Future<SSHClient> _connect(ServerConfig server) async {
    final socket = await SSHSocket.connect(server.host, server.port);

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

  /// Выполняет произвольную команду на сервере и возвращает её stdout.
  Future<String> _runCommand(SSHClient client, String command) async {
    final result = await client.execute(command);
    final output = await utf8.decoder.bind(result.stdout).join();
    result.close();
    return output;
  }

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
    );
  }
}
