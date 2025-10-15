import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/log_entry.dart';
import '../models/server_config.dart';
import '../providers/app_providers.dart';
import '../widgets/log_entry_tile.dart';

class ServerDetailArguments {
  const ServerDetailArguments({required this.server});

  final ServerConfig server;
}

class ServerDetailScreen extends ConsumerStatefulWidget {
  const ServerDetailScreen({super.key, required this.args});

  static const routeName = '/detail';

  final ServerDetailArguments args;

  @override
  ConsumerState<ServerDetailScreen> createState() => _ServerDetailScreenState();
}

class _ServerDetailScreenState extends ConsumerState<ServerDetailScreen> {
  final _logs = <LogEntry>[];
  StreamSubscription<LogEntry>? _subscription;
  List<String> _services = <String>[];
  String? _selectedService;
  bool _isLoadingServices = true;
  bool _isStreaming = false;
  String _filter = '';
  late ServerConfig _server;

  @override
  void initState() {
    super.initState();
    _server = widget.args.server;
    _loadServices();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_server.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить сервисы',
            onPressed: _isLoadingServices ? null : _loadServices,
          ),
          IconButton(
            icon: Icon(_isStreaming ? Icons.stop_circle_outlined : Icons.play_circle_outline),
            tooltip: _isStreaming ? 'Остановить поток' : 'Переподключиться',
            onPressed: (_selectedService == null || !settingsAsync.hasValue)
                ? null
                : () => _restartStream(settingsAsync.requireValue),
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
                Text('${_server.username}@${_server.host}:${_server.port}',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 12),
                _buildServiceDropdown(settingsAsync),
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
            child: _buildLogList(),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceDropdown(AsyncValue<AppSettings> settingsAsync) {
    if (_isLoadingServices) {
      return const LinearProgressIndicator();
    }
    if (_services.isEmpty) {
      return const Text('Сервисы не найдены или доступ запрещен.');
    }
    return DropdownButtonFormField<String>(
      initialValue: _selectedService ?? _server.defaultService,
      decoration: const InputDecoration(labelText: 'Сервис'),
      items: _services
          .map(
            (service) => DropdownMenuItem(
              value: service,
              child: Text(service),
            ),
          )
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedService = value;
        });
        if (value != null) {
          final updated = _server.copyWith(defaultService: value);
          _server = updated;
          ref.read(serverListProvider.notifier).update(updated);
        }
      },
    );
  }

  Widget _buildLogList() {
    if (_selectedService == null) {
      return const Center(child: Text('Выберите сервис, чтобы увидеть логи.'));
    }
    final serviceLogs =
        _logs.where((log) => log.service == _selectedService).toList(growable: false);
    if (serviceLogs.isEmpty) {
      return const Center(child: Text('Ждём новых записей журнала...'));
    }
    final filtered = _filter.isEmpty
        ? serviceLogs
        : serviceLogs
            .where((log) => log.message.toLowerCase().contains(_filter.toLowerCase()))
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
          isEven: reversedIndex.isEven,
        );
      },
    );
  }

  Future<void> _loadServices() async {
    setState(() {
      _isLoadingServices = true;
    });
    final server = _server;
    try {
      final services = await ref.read(sshServiceProvider).fetchServices(server);
      setState(() {
        _services = services;
        _selectedService = server.defaultService != null && services.contains(server.defaultService)
            ? server.defaultService
            : (services.isNotEmpty ? services.first : null);
      });
      final settings = ref.read(settingsProvider).maybeWhen(data: (value) => value, orElse: () => null);
      if (_selectedService != null && settings != null) {
        _restartStream(settings);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить сервисы: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingServices = false;
        });
      }
    }
  }

  Future<void> _restartStream(AppSettings settings) async {
    await _subscription?.cancel();
    _logs.clear();
    setState(() {
      _isStreaming = false;
    });

    if (_selectedService == null || _services.isEmpty) {
      return;
    }

    final sshService = ref.read(sshServiceProvider);
    final stream = sshService.streamLogs(_server, _services, settings);
    _subscription = stream.listen(
      (event) {
        setState(() {
          _logs.add(event);
          _isStreaming = true;
        });
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка потока логов: $error')),
          );
        }
        setState(() {
          _isStreaming = false;
        });
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isStreaming = false;
          });
        }
      },
    );
  }
}
