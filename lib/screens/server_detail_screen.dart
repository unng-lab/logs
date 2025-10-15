import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/log_entry.dart';
import '../models/server_config.dart';
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

  @override
  void initState() {
    super.initState();
    final server = widget.args.server;
    ref.listen(serverDetailControllerProvider(server), (previous, next) {
      final prevError = previous?.valueOrNull?.errorMessage;
      final newError = next.valueOrNull?.errorMessage;
      if (newError != null && newError != prevError && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newError)),
        );
      }
    });
  }

  /// Строит основной интерфейс экрана с фильтрами и списком логов.
  @override
  Widget build(BuildContext context) {
    final server = widget.args.server;
    final controllerAsync = ref.watch(serverDetailControllerProvider(server));
    final controller = ref.read(serverDetailControllerProvider(server).notifier);
    final state = controllerAsync.valueOrNull;

    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: Text(server.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(server.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить сервисы',
            onPressed: state.isLoadingServices ? null : controller.refreshServices,
          ),
          IconButton(
            icon: Icon(state.isStreaming ? Icons.stop_circle_outlined : Icons.play_circle_outline),
            tooltip: state.isStreaming ? 'Остановить поток' : 'Переподключиться',
            onPressed: (state.selectedService == null || state.isLoadingServices)
                ? null
                : controller.toggleStreaming,
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
                _buildServiceDropdown(state, controller),
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
            child: _buildLogList(state),
          ),
        ],
      ),
    );
  }

  /// Создаёт выпадающий список сервисов или отображает состояние загрузки.
  Widget _buildServiceDropdown(ServerDetailState state, ServerDetailController controller) {
    if (state.isLoadingServices) {
      return const LinearProgressIndicator();
    }
    if (state.services.isEmpty) {
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
      onChanged: controller.selectService,
    );
  }

  /// Формирует список логов с учётом выбранного сервиса и текстового фильтра.
  Widget _buildLogList(ServerDetailState state) {
    final selectedService = state.selectedService;
    if (selectedService == null) {
      return const Center(child: Text('Выберите сервис, чтобы увидеть логи.'));
    }

    final serviceLogs = state.logs
        .where((log) => log.service == selectedService)
        .toList(growable: false);
    if (serviceLogs.isEmpty) {
      return const Center(child: Text('Ждём новых записей журнала...'));
    }

    final filtered = _filter.isEmpty
        ? serviceLogs
        : serviceLogs
            .where((log) => _matchesFilter(log, _filter))
            .toList(growable: false);
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
          isEven: index.isEven,
        );
      },
    );
  }

  bool _matchesFilter(LogEntry log, String filter) {
    return log.message.toLowerCase().contains(filter.toLowerCase());
  }
}
