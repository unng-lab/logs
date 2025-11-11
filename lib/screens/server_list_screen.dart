import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/server_config.dart';
import '../models/metrics.dart';
import '../providers/app_providers.dart';
import 'edit_server_screen.dart';
import 'server_detail_screen.dart';
import 'settings_screen.dart';

/// Главный экран со списком добавленных серверов и их статусами.
class ServerListScreen extends ConsumerWidget {
  const ServerListScreen({super.key});

  static const routeName = '/';

  /// Строит список серверов и отображает состояние загрузки или ошибок.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversAsync = ref.watch(serverListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () =>
                Navigator.of(context).pushNamed(SettingsScreen.routeName),
          ),
        ],
      ),
      body: serversAsync.when(
        data: (servers) {
          if (servers.isEmpty) {
            return _EmptyState(onAdd: () => _openEditor(context));
          }
          return ListView.separated(
            itemBuilder: (context, index) {
              final server = servers[index];
              return ServerListTile(
                key: ValueKey(server.id),
                server: server,
                onOpenDetail: () => _openDetail(context, server),
                onOpenEditor: () => _openEditor(context, server: server),
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: servers.length,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Failed to load servers: $error'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Add server'),
      ),
    );
  }

  /// Открывает экран добавления или редактирования сервера.
  void _openEditor(BuildContext context, {ServerConfig? server}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditServerScreen(server: server),
        fullscreenDialog: true,
      ),
    );
  }

  /// Переходит на экран детализации выбранного сервера.
  void _openDetail(BuildContext context, ServerConfig server) {
    Navigator.of(context).pushNamed(
      ServerDetailScreen.routeName,
      arguments: ServerDetailArguments(server: server),
    );
  }
}

/// Отдельная плитка списка сервера, реагирующая на обновления провайдеров.
class ServerListTile extends ConsumerWidget {
  const ServerListTile({
    super.key,
    required this.server,
    required this.onOpenDetail,
    required this.onOpenEditor,
  });

  final ServerConfig server;
  final VoidCallback onOpenDetail;
  final VoidCallback onOpenEditor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(serverStatusProvider(server));

    return statusAsync.when(
      data: (isOnline) {
        if (!isOnline) {
          return _buildTile(
            context,
            statusText: 'Отключен',
            statusColor: Colors.red,
            details: [
              _buildDetailText(context, 'Скорость журнала: недоступна'),
            ],
          );
        }

        final logRateAsync = ref.watch(serverLogRateProvider(server));
        final logRateText = logRateAsync.when(
          data: (rate) {
            if (rate <= 0) {
              return 'Скорость журнала: нет новых записей';
            }
            final formatted = _formatLogRate(rate);
            return 'Скорость журнала: ~$formatted записей/с';
          },
          loading: () => 'Скорость журнала: считаем…',
          error: (error, _) => 'Скорость журнала: ошибка (${error.toString()})',
        );

        final metricsAsync = ref.watch(serverMetricsProvider(server));
        final details = <Widget>[
          _buildDetailText(context, logRateText),
        ];
        final metricsWidget = metricsAsync.when(
          data: (metrics) {
            final formatted = _formatServerMetrics(metrics);
            if (formatted == null) {
              return const SizedBox.shrink();
            }
            return _buildDetailText(context, formatted);
          },
          loading: () =>
              _buildDetailText(context, 'Метрики: обновляем данные...'),
          error: (error, _) => _buildDetailText(
              context, 'Метрики: ошибка (${error.toString()})'),
        );
        if (metricsWidget is! SizedBox) {
          details.add(metricsWidget);
        }
        return _buildTile(
          context,
          statusText: 'Онлайн',
          statusColor: Colors.green,
          details: details,
        );
      },
      loading: () => _buildTile(
        context,
        statusText: 'Проверяем подключение...',
        statusColor: Colors.orange,
        details: [
          _buildDetailText(context, 'Скорость журнала: проверяем...'),
        ],
      ),
      error: (error, _) => _buildTile(
        context,
        statusText: 'Ошибка проверки подключения',
        statusColor: Colors.red,
        details: [
          _buildDetailText(context, 'Скорость журнала: недоступна'),
        ],
      ),
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required String statusText,
    required Color statusColor,
    List<Widget> details = const <Widget>[],
  }) {
    return ListTile(
      leading: Icon(Icons.dns_outlined, color: statusColor),
      title: Text(server.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${server.username}@${server.host}:${server.port}'),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.circle, size: 10, color: statusColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(color: statusColor),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          for (final detail in details) ...[
            const SizedBox(height: 4),
            detail,
          ],
        ],
      ),
      onTap: onOpenDetail,
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        onPressed: onOpenEditor,
      ),
    );
  }

  String _formatLogRate(double rate) {
    if (rate.isNaN || rate.isInfinite) {
      return '0';
    }
    if (rate >= 100) {
      return rate.toStringAsFixed(0);
    }
    if (rate >= 10) {
      return rate.toStringAsFixed(1);
    }
    return rate.toStringAsFixed(2);
  }

  Widget _buildDetailText(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  String? _formatServerMetrics(ServerMetrics metrics) {
    final cpu = metrics.cpuUsagePercent;
    final memoryPercent = metrics.memoryUsagePercent;
    final memoryTotal = metrics.memoryTotalBytes;
    final memoryUsed = metrics.memoryUsedBytes;
    if (cpu == null &&
        memoryPercent == null &&
        memoryTotal == null &&
        memoryUsed == null) {
      return null;
    }
    final cpuText = cpu != null ? 'CPU: ${cpu.toStringAsFixed(1)}%' : 'CPU: —';

    String memoryText;
    if (memoryPercent != null) {
      final percentText = memoryPercent.toStringAsFixed(1);
      if (memoryTotal != null && memoryUsed != null && memoryTotal > 0) {
        final usedText = _formatBytes(memoryUsed);
        final totalText = _formatBytes(memoryTotal);
        memoryText = 'RAM: $percentText% ($usedText / $totalText)';
      } else {
        memoryText = 'RAM: $percentText%';
      }
    } else if (memoryTotal != null && memoryUsed != null && memoryTotal > 0) {
      final percent = (memoryUsed / memoryTotal) * 100;
      final percentText = percent.clamp(0, 100).toStringAsFixed(1);
      final usedText = _formatBytes(memoryUsed);
      final totalText = _formatBytes(memoryTotal);
      memoryText = 'RAM: $percentText% ($usedText / $totalText)';
    } else if (memoryUsed != null) {
      memoryText = 'RAM: ${_formatBytes(memoryUsed)}';
    } else if (memoryTotal != null) {
      memoryText = 'RAM: ${_formatBytes(memoryTotal)} всего';
    } else {
      memoryText = 'RAM: —';
    }

    return '$cpuText · $memoryText';
  }

  String _formatBytes(int bytes) {
    const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final precision = value >= 10 ? 0 : 1;
    return '${value.toStringAsFixed(precision)} ${units[unitIndex]}';
  }
}

/// Состояние пустого списка серверов с подсказкой.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  /// Показывает призыв к действию при отсутствии серверов.
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Добавьте ваш первый сервер',
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Приложение подключается по SSH, обнаруживает systemd сервисы и показывает журналы в реальном времени.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Добавить сервер'),
            ),
          ],
        ),
      ),
    );
  }
}
