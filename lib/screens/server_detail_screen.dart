import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/log_entry.dart';
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
            icon: Icon(
              (controllerState.valueOrNull?.isStreaming ?? false)
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline,
            ),
            tooltip: (controllerState.valueOrNull?.isStreaming ?? false)
                ? 'Остановить поток'
                : 'Переподключиться',
            onPressed: (controllerState.valueOrNull?.selectedService == null ||
                    !settingsAsync.hasValue)
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
    return DropdownButtonFormField<String>(
      value: state.selectedService,
      decoration: const InputDecoration(labelText: 'Сервис'),
      items: state.services
          .map(
            (service) => DropdownMenuItem(
              value: service,
              child: Text(service),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          ref
              .read(serverDetailControllerProvider(widget.args.server).notifier)
              .selectService(value);
        }
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
    final selectedService = state?.selectedService;
    if (selectedService == null) {
      return const Center(child: Text('Выберите сервис, чтобы увидеть логи.'));
    }
    final serviceLogs = state?.logs
            .where((log) => log.service == selectedService)
            .toList(growable: false) ??
        const <LogEntry>[];
    if (serviceLogs.isEmpty) {
      return const Center(child: Text('Ждём новых записей журнала...'));
    }
    final filtered = _filter.isEmpty
        ? serviceLogs
        : serviceLogs
            .where((log) =>
                log.message.toLowerCase().contains(_filter.toLowerCase()))
            .toList();
    if (filtered.isEmpty) {
      return const Center(child: Text('По фильтру ничего не найдено.'));
    }

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
  }
}
