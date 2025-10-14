import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:intl/intl.dart';

import '../models/app_settings.dart';
import '../models/log_entry.dart';
import '../models/server_config.dart';

/// Provides convenience utilities for establishing SSH connections and
/// retrieving information from remote servers.
class SSHService {
  /// Opens an SSH connection using the provided [server] configuration.
  Future<SSHClient> _connect(ServerConfig server) async {
    final socket = await SSHSocket.connect(server.host, server.port);
    final identity = _buildIdentity(server);

    return SSHClient(
      socket,
      username: server.username,
      identity: identity,
      onPasswordRequest: () => server.password ?? '',
    );
  }

  /// Builds an [SSHKeyPair] when a private key is supplied.
  SSHKeyPair? _buildIdentity(ServerConfig server) {
    final privateKey = server.privateKey;
    if (privateKey == null || privateKey.trim().isEmpty) {
      return null;
    }

    return SSHKeyPair.fromPem(
      privateKey,
      server.passphrase ?? '',
    );
  }

  /// Executes the [command] and returns its standard output as a [String].
  Future<String> _runCommand(SSHClient client, String command) async {
    final session = await client.execute(command);
    try {
      final stdout = utf8.decoder.bind(session.stdout);
      return await stdout.join();
    } finally {
      await session.close();
    }
  }

  /// Retrieves a sorted list of running systemd services.
  Future<List<String>> fetchServices(ServerConfig server) async {
    final client = await _connect(server);
    try {
      const command =
          "systemctl list-units --type=service --state=running --no-legend --no-pager | awk '{print \$1}'";
      final output = await _runCommand(client, command);
      final services = output
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      services.sort();
      return services;
    } finally {
      await client.close();
    }
  }

  /// Streams journalctl output for a given [service].
  Stream<LogEntry> streamLogs(
    ServerConfig server,
    String service,
    AppSettings settings,
  ) {
    final controller = StreamController<LogEntry>.broadcast();
    SSHClient? client;
    SSHSession? session;
    StreamSubscription<String>? subscription;

    Future<void> closeResources() async {
      await subscription?.cancel();
      if (session != null) {
        await session!.close();
      }
      await client?.close();
    }

    controller
      ..onListen = () async {
        client = await _connect(server);
        final command = _buildJournalCommand(service, settings.logRetentionDays);
        session = await client!.execute(command);

        final lines = utf8
            .decoder
            .bind(session!.stdout)
            .transform(const LineSplitter());

        subscription = lines.listen(
          (line) => _handleLogLine(controller, service, line),
          onError: controller.addError,
          onDone: () async {
            await closeResources();
            if (!controller.isClosed) {
              await controller.close();
            }
          },
          cancelOnError: false,
        );
      }
      ..onCancel = () async {
        await closeResources();
        if (!controller.isClosed) {
          await controller.close();
        }
      }
      ..onPause = () => subscription?.pause()
      ..onResume = () => subscription?.resume();

    return controller.stream;
  }

  /// Creates the journalctl command for the provided [service].
  String _buildJournalCommand(String service, int logRetentionDays) {
    final since = DateTime.now().subtract(Duration(days: logRetentionDays));
    final formatted = DateFormat('yyyy-MM-dd HH:mm:ss').format(since.toUtc());
    return 'journalctl -u $service --since "$formatted UTC" -o json --follow --no-pager';
  }

  /// Processes a single line of journal output and pushes it to the [controller].
  void _handleLogLine(
    StreamController<LogEntry> controller,
    String service,
    String line,
  ) {
    if (line.trim().isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(line) as Map<String, dynamic>;
      final entry = _mapJsonToEntry(decoded, service);
      controller.add(entry);
    } catch (_) {
      // Ignore malformed JSON records from journalctl.
    }
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
