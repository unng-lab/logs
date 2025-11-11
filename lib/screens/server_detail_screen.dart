import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/log_entry.dart';
import '../models/metrics.dart';
import '../models/server_config.dart';
import '../providers/app_providers.dart';
import '../providers/server_detail_controller.dart';
import '../widgets/log_entry_tile.dart';

/// Аргументы для экрана детальной информации о сервере.
class ServerDetailArguments {
  const ServerDetailArguments({required this.server});

  final ServerConfig server;
}

/// Экран просмотра журналов конкретного сервера и управления потоками.
class ServerDetailScreen extends ConsumerStatefulWidget {
  const ServerDetailScreen({super.key, required this.args});

  static const routeName = '/detail';

  final ServerDetailArguments args;

  @override
  ConsumerState<ServerDetailScreen> createState() => _ServerDetailScreenState();
}

class _ServerDetailScreenState extends ConsumerState<ServerDetailScreen> {
  String _filter = '';
  late final ScrollController _logScrollController;
  bool _isAtEnd = true;

  @override
  void initState() {
    super.initState();
    _logScrollController = ScrollController()
      ..addListener(_handleLogScrollPositionChange);
  }

  @override
  void dispose() {
    _logScrollController
      ..removeListener(_handleLogScrollPositionChange)
      ..dispose();
    super.dispose();
  }

  void _handleLogScrollPositionChange() {
    if (!_logScrollController.hasClients) {
      return;
    }
    final isAtEnd = _logScrollController.offset <= 32;
    if (isAtEnd != _isAtEnd && mounted) {
      setState(() {
        _isAtEnd = isAtEnd;
      });
    }
  }

  void _scrollLogsToEnd() {
    if (!_logScrollController.hasClients) {
      return;
    }
    _logScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Строит основной интерфейс экрана с фильтрами и списком логов.
  @override
  Widget build(BuildContext context) {
    final server = widget.args.server;
    final controllerProvider = serverDetailControllerProvider(server);
    ref.listen<AsyncValue<ServerDetailState>>(controllerProvider,
        (previous, next) {
      final previousAlertId = previous?.value?.alert?.id;
      final alert = next.value?.alert;
      if (alert != null && alert.id != previousAlertId) {
        if (!mounted) {
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(alert.message),
            backgroundColor:
                alert.isError ? Theme.of(context).colorScheme.error : null,
          ),
        );
        ref.read(controllerProvider.notifier).clearAlert();
      }
    });
    final controllerState = ref.watch(controllerProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final selectedService = controllerState.valueOrNull?.selectedService;

    final isServicesLoading =
        controllerState.valueOrNull?.isLoadingServices ?? false;
    final isInitialLoading =
        controllerState.isLoading && controllerState.valueOrNull == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(server.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить сервисы',
            onPressed: (isServicesLoading || isInitialLoading)
                ? null
                : () => ref.read(controllerProvider.notifier).refreshServices(),
          ),
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Перезапустить поток',
            onPressed: (!settingsAsync.hasValue ||
                    (controllerState.valueOrNull?.services.isEmpty ?? true))
                ? null
                : () => ref.read(controllerProvider.notifier).toggleStreaming(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${server.username}@${server.host}:${server.port}',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 12),
                _buildServiceDropdown(controllerState),
                if (selectedService != null) ...[
                  const SizedBox(height: 12),
                  _ServiceMetricsInfo(
                    server: server,
                    service: selectedService,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Фильтр по тексту',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => _filter = value.trim()),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildLogList(controllerState),
          ),
        ],
      ),
    );
  }

  /// Создаёт выпадающий список сервисов или отображает состояние загрузки.
  Widget _buildServiceDropdown(AsyncValue<ServerDetailState> controllerState) {
    final state = controllerState.valueOrNull;
    final isLoading = state?.isLoadingServices ?? controllerState.isLoading;
    if (isLoading) {
      return const LinearProgressIndicator();
    }
    if (controllerState.hasError && state == null) {
      return const Text('Не удалось загрузить сервисы.');
    }
    if (state == null || state.services.isEmpty) {
      return const Text('Сервисы не найдены или доступ запрещен.');
    }
    final selectedService = state.selectedService;
    return DropdownButtonFormField<String?>(
      key: ValueKey<String>('service:${selectedService ?? 'all'}'),
      initialValue: selectedService,
      decoration: const InputDecoration(labelText: 'Сервис'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Все логи'),
        ),
        ...state.services.map(
          (service) => DropdownMenuItem<String?>(
            value: service,
            child: Text(service),
          ),
        ),
      ],
      onChanged: (value) {
        final notifier = ref
            .read(serverDetailControllerProvider(widget.args.server).notifier);
        notifier.selectService(value);
      },
    );
  }

  /// Формирует список логов с учётом выбранного сервиса и текстового фильтра.
  Widget _buildLogList(AsyncValue<ServerDetailState> controllerState) {
    final state = controllerState.valueOrNull;
    if (controllerState.isLoading && state == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controllerState.hasError && state == null) {
      return const Center(child: Text('Не удалось загрузить данные.'));
    }
    final allLogs = state?.logs ?? const <LogEntry>[];
    if (allLogs.isEmpty) {
      return const Center(child: Text('Ждём новых записей журнала...'));
    }

    final selectedService = state?.selectedService;
    final serviceLogs = selectedService == null
        ? allLogs
        : allLogs
            .where((log) => log.service == selectedService)
            .toList(growable: false);

    if (serviceLogs.isEmpty) {
      return Center(
        child: Text(
          selectedService == null
              ? 'Ждём новых записей журнала...'
              : 'Для выбранного сервиса пока нет записей.',
        ),
      );
    }

    final normalizedFilter = _filter.toLowerCase();
    final filtered = normalizedFilter.isEmpty
        ? serviceLogs
        : serviceLogs
            .where(
              (log) => log.message.toLowerCase().contains(normalizedFilter),
            )
            .toList(growable: false);
    if (filtered.isEmpty) {
      return const Center(child: Text('По фильтру ничего не найдено.'));
    }

    final logListView = ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      controller: _logScrollController,
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final reversedIndex = filtered.length - 1 - index;
        final entry = filtered[reversedIndex];
        return LogEntryTile(
          entry: entry,
          // Используем индекс элемента в текущем представлении списка, чтобы
          // зебра корректно обновлялась при поступлении новых сообщений.
          isEven: index.isEven,
        );
      },
    );

    final isMobilePlatform = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.fuchsia;
    final shouldUseSelectionArea = kIsWeb || !isMobilePlatform;

    Widget logContent = logListView;
    if (shouldUseSelectionArea) {
      logContent = SelectionArea(child: logContent);
    }

    return Stack(
      children: [
        Positioned.fill(child: logContent),
        if (!_isAtEnd)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.small(
              onPressed: _scrollLogsToEnd,
              tooltip: 'В конец',
              child: const Icon(Icons.arrow_downward),
            ),
          ),
      ],
    );
  }
}

class _ServiceMetricsInfo extends ConsumerWidget {
  const _ServiceMetricsInfo({
    required this.server,
    required this.service,
  });

  final ServerConfig server;
  final String service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(
      serviceMetricsProvider(
        ServiceMetricsRequest(server: server, service: service),
      ),
    );

    return metricsAsync.when(
      data: (metrics) {
        final content = <Widget>[
          Text(
            _formatMetricsLine(metrics),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ];
        final pid = metrics.pid;
        if (pid != null && pid > 0) {
          content.add(
            Text(
              'PID: $pid',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return _MetricsCard(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: content,
        ));
      },
      loading: () => _MetricsCard(
        child: const Text('Загружаем метрики сервиса...'),
      ),
      error: (error, _) => _MetricsCard(
        child: Text('Метрики недоступны: ${error.toString()}'),
      ),
    );
  }

  String _formatMetricsLine(ServiceMetrics metrics) {
    final cpuText = metrics.cpuUsagePercent != null
        ? 'CPU: ${metrics.cpuUsagePercent!.toStringAsFixed(1)}%'
        : 'CPU: —';
    final memoryPercent = metrics.memoryUsagePercent;
    final memoryUsage = memoryPercent != null
        ? 'RAM: ${memoryPercent.toStringAsFixed(1)}%'
        : 'RAM: —';
    final rss = metrics.memoryRssBytes;
    final rssSuffix = rss != null ? ' (~${_formatBytes(rss)})' : '';
    return '$cpuText · $memoryUsage$rssSuffix';
  }

  String _formatBytes(int bytes) {
    const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unitIndex]}';
  }
}

class _MetricsCard extends StatelessWidget {
  const _MetricsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: child,
      ),
    );
  }
}
