import 'package:intl/intl.dart';

/// Уровни важности записей systemd журнала.
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

/// Модель данных одной записи журнала systemd.
class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.message,
    required this.severity,
    required this.service,
    required this.raw,
    required this.receivedAt,
    this.realtimeTimestampMicros,
    bool? isFresh,
  }) : isFresh = isFresh ?? false;

  final DateTime timestamp;
  final String message;
  final LogSeverity severity;
  final String service;
  final Map<String, dynamic> raw;
  final String? realtimeTimestampMicros;
  final DateTime receivedAt;

  /// Показывает, что запись была получена менее 5 секунд назад.
  final bool isFresh;

  /// Создаёт копию записи с возможностью обновления отдельных полей.
  LogEntry copyWith({
    DateTime? timestamp,
    String? message,
    LogSeverity? severity,
    String? service,
    Map<String, dynamic>? raw,
    String? realtimeTimestampMicros,
    DateTime? receivedAt,
    bool? isFresh,
  }) {
    return LogEntry(
      timestamp: timestamp ?? this.timestamp,
      message: message ?? this.message,
      severity: severity ?? this.severity,
      service: service ?? this.service,
      raw: raw ?? this.raw,
      realtimeTimestampMicros:
          realtimeTimestampMicros ?? this.realtimeTimestampMicros,
      receivedAt: receivedAt ?? this.receivedAt,
      isFresh: isFresh ?? this.isFresh,
    );
  }

  /// Форматированная временная метка с точностью до секунд.
  String get formattedTimestamp {
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    return formatter.format(timestamp.toLocal());
  }

  /// Форматированная realtime-метка из поля `__REALTIME_TIMESTAMP`.
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

  /// Преобразует приоритет systemd к перечислению [LogSeverity].
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
