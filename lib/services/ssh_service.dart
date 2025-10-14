import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:intl/intl.dart';

import '../models/app_settings.dart';
import '../models/log_entry.dart';
import '../models/server_config.dart';

class SSHService {
  Future<SSHClient> _connect(ServerConfig server) async {
    final socket = await SSHSocket.connect(server.host, server.port);

    final identities = <SSHKeyPair>[];
    if (server.privateKey != null && server.privateKey!.trim().isNotEmpty) {
      final keyPair = SSHKeyPair.fromPem(
        server.privateKey!,
        server.passphrase ?? '',
      );
      identities.add(keyPair);
    }

    return SSHClient(
      socket,
      username: server.username,
      identities: identities.isEmpty ? null : identities,
      onPasswordRequest: () => server.password ?? '',
    );
  }

  Future<List<String>> fetchServices(ServerConfig server) async {
    final client = await _connect(server);
    try {
      final command =
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

  Stream<LogEntry> streamLogs(
    ServerConfig server,
    String service,
    AppSettings settings,
  ) {
    final controller = StreamController<LogEntry>.broadcast();
    SSHClient? client;
    SSHSession? channel;
    StreamSubscription<String>? subscription;

    Future<void> closeResources() async {
      await subscription?.cancel();
      channel?.close();
      client?.close();
    }

    controller.onListen = () async {
      client = await _connect(server);
      final since = DateTime.now().subtract(Duration(days: settings.logRetentionDays));
      final sinceFormatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(since.toUtc());
      final command =
          'journalctl -u $service --since "$sinceFormatted UTC" -o json --follow --no-pager';
      channel = await client!.execute(command);
      final stdout = utf8
          .decoder
          .bind(channel!.stdout)
          .transform(const LineSplitter());
      subscription = stdout.listen(
        (line) {
          if (line.trim().isEmpty) {
            return;
          }
          try {
            final decoded = jsonDecode(line) as Map<String, dynamic>;
            final entry = _mapJsonToEntry(decoded, service);
            controller.add(entry);
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

    controller.onPause = () {
      subscription?.pause();
    };

    controller.onResume = () {
      subscription?.resume();
    };

    return controller.stream;
  }

  Future<String> _runCommand(SSHClient client, String command) async {
    final result = await client.execute(command);
    final output = await utf8.decoder.bind(result.stdout).join();
    result.close();
    return output;
  }

  LogEntry _mapJsonToEntry(Map<String, dynamic> json, String service) {
    final message = (json['MESSAGE'] as String?) ?? '';
    final timestampMicros = int.tryParse(json['__REALTIME_TIMESTAMP']?.toString() ?? '');
    final timestamp = timestampMicros != null
        ? DateTime.fromMicrosecondsSinceEpoch(timestampMicros, isUtc: true)
        : DateTime.now().toUtc();
    final severity = LogEntry.severityFromPriority(json['PRIORITY']?.toString());
    return LogEntry(
      timestamp: timestamp,
      message: message,
      severity: severity,
      service: service,
      raw: json,
    );
  }
}
