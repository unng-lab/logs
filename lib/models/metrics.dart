import 'package:flutter/foundation.dart';

import 'server_config.dart';

/// Информация о загрузке всего сервера.
@immutable
class ServerMetrics {
  const ServerMetrics({
    this.cpuUsagePercent,
    this.memoryUsagePercent,
    this.memoryTotalBytes,
    this.memoryUsedBytes,
  });

  /// Текущая загрузка CPU в процентах.
  final double? cpuUsagePercent;

  /// Использование оперативной памяти в процентах.
  final double? memoryUsagePercent;

  /// Общий объём оперативной памяти в байтах.
  final int? memoryTotalBytes;

  /// Используемый объём оперативной памяти в байтах.
  final int? memoryUsedBytes;

  ServerMetrics copyWith({
    double? cpuUsagePercent,
    double? memoryUsagePercent,
    int? memoryTotalBytes,
    int? memoryUsedBytes,
  }) {
    return ServerMetrics(
      cpuUsagePercent: cpuUsagePercent ?? this.cpuUsagePercent,
      memoryUsagePercent: memoryUsagePercent ?? this.memoryUsagePercent,
      memoryTotalBytes: memoryTotalBytes ?? this.memoryTotalBytes,
      memoryUsedBytes: memoryUsedBytes ?? this.memoryUsedBytes,
    );
  }
}

/// Информация о загрузке конкретного systemd-сервиса.
@immutable
class ServiceMetrics {
  const ServiceMetrics({
    this.cpuUsagePercent,
    this.memoryUsagePercent,
    this.memoryRssBytes,
    this.pid,
  });

  /// Текущая загрузка CPU процесса главного PID.
  final double? cpuUsagePercent;

  /// Использование оперативной памяти в процентах от общего объёма.
  final double? memoryUsagePercent;

  /// Потребление памяти RSS в байтах.
  final int? memoryRssBytes;

  /// Главный PID сервиса, если удалось определить.
  final int? pid;

  ServiceMetrics copyWith({
    double? cpuUsagePercent,
    double? memoryUsagePercent,
    int? memoryRssBytes,
    int? pid,
  }) {
    return ServiceMetrics(
      cpuUsagePercent: cpuUsagePercent ?? this.cpuUsagePercent,
      memoryUsagePercent: memoryUsagePercent ?? this.memoryUsagePercent,
      memoryRssBytes: memoryRssBytes ?? this.memoryRssBytes,
      pid: pid ?? this.pid,
    );
  }
}

/// Ключ для провайдера метрик сервиса.
@immutable
class ServiceMetricsRequest {
  const ServiceMetricsRequest({
    required this.server,
    required this.service,
  });

  final ServerConfig server;
  final String service;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ServiceMetricsRequest &&
        other.service == service &&
        other.server.id == server.id;
  }

  @override
  int get hashCode => Object.hash(server.id, service);
}
