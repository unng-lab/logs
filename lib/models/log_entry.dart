import 'package:intl/intl.dart';

enum LogSeverity {
  emergency,
  alert,
  critical,
  error,
  warning,
  notice,
  info,
  debug,
}

class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.message,
    required this.severity,
    required this.service,
    required this.raw,
    this.realtimeTimestampMicros,
  });

  final DateTime timestamp;
  final String message;
  final LogSeverity severity;
  final String service;
  final Map<String, dynamic> raw;
  final String? realtimeTimestampMicros;

  String get formattedTimestamp {
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    return formatter.format(timestamp.toLocal());
  }

  String get formattedRealtimeTimestamp {
    final micros = int.tryParse(realtimeTimestampMicros ?? '');
    if (micros == null) {
      return '-';
    }
    final realtime =
        DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true).toLocal();
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss.SSSSSS');
    return formatter.format(realtime);
  }

  static LogSeverity severityFromPriority(String? priority) {
    switch (priority) {
      case '0':
        return LogSeverity.emergency;
      case '1':
        return LogSeverity.alert;
      case '2':
        return LogSeverity.critical;
      case '3':
        return LogSeverity.error;
      case '4':
        return LogSeverity.warning;
      case '5':
        return LogSeverity.notice;
      case '6':
        return LogSeverity.info;
      case '7':
      default:
        return LogSeverity.debug;
    }
  }
}
