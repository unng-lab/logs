import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/log_entry.dart';
import '../models/server_config.dart';
import 'app_providers.dart';

/// Максимальное количество записей в буфере логов для одного сервера.
const _maxBufferedEntries = 500;

/// Состояние фоновой подписки на журналы сервера.
class ServerLogsState {
  const ServerLogsState({
    this.services = const <String>[],
    this.logs = const <LogEntry>[],
    this.isStreaming = false,
    this.isLoadingServices = true,
  });

  final List<String> services;
  final List<LogEntry> logs;
  final bool isStreaming;
  final bool isLoadingServices;

  ServerLogsState copyWith({
    List<String>? services,
    List<LogEntry>? logs,
    bool? isStreaming,
    bool? isLoadingServices,
  }) {
    return ServerLogsState(
      services: services ?? this.services,
      logs: logs ?? this.logs,
      isStreaming: isStreaming ?? this.isStreaming,
      isLoadingServices: isLoadingServices ?? this.isLoadingServices,
    );
  }
}

/// Провайдер, который в фоне поддерживает SSH-подписку на журналы сервера и
/// хранит ограниченный буфер полученных записей.
final serverLogsProvider = AsyncNotifierProviderFamily<ServerLogsNotifier,
    ServerLogsState, ServerConfig>(ServerLogsNotifier.new);

class ServerLogsNotifier
    extends FamilyAsyncNotifier<ServerLogsState, ServerConfig> {
  ServerConfig? _server;
  StreamSubscription<LogEntry>? _subscription;
  AppSettings? _cachedSettings;
  int? _lastInitialLines;

  @override
  FutureOr<ServerLogsState> build(ServerConfig arg) async {
    _server = arg;
    ref.onDispose(() async {
      await _subscription?.cancel();
      _subscription = null;
    });

    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
      final settings = next.valueOrNull;
      if (settings == null) {
        return;
      }
      final current = state.valueOrNull;
      if (current == null || current.services.isEmpty) {
        _cachedSettings = settings;
        _lastInitialLines = settings.initialLogLines;
        return;
      }
      final hasSettingsChanged =
          _lastInitialLines != settings.initialLogLines ||
              _cachedSettings == null;
      _cachedSettings = settings;
      _lastInitialLines = settings.initialLogLines;
      if (!hasSettingsChanged) {
        return;
      }
      if (current.isStreaming) {
        unawaited(_restartStreaming(current.services, settings));
      } else {
        unawaited(_startStreaming(current.services, settings));
      }
    });

    try {
      final services = await _fetchServices();
      var currentState = ServerLogsState(
        services: services,
        logs: const <LogEntry>[],
        isStreaming: false,
        isLoadingServices: false,
      );
      state = AsyncValue.data(currentState);

      final settings = _readSettings();
      if (settings == null || services.isEmpty) {
        return currentState;
      }
      await _startStreaming(services, settings);
      currentState = state.requireValue;
      return currentState;
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
      return Future.error(error, stackTrace);
    }
  }

  /// Принудительно обновляет список сервисов и перезапускает поток логов.
  Future<void> refreshServices() async {
    final previous = state.valueOrNull ?? const ServerLogsState();
    state = AsyncValue.data(
      previous.copyWith(isLoadingServices: true),
    );
    try {
      final services = await _fetchServices();
      final updated = previous.copyWith(
        services: services,
        isLoadingServices: false,
        logs: const <LogEntry>[],
      );
      state = AsyncValue.data(updated);
      final settings = _readSettings();
      if (settings != null && services.isNotEmpty) {
        await _restartStreaming(services, settings);
      }
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Перезапускает текущий поток логов.
  Future<void> restart() async {
    final current = state.valueOrNull;
    final settings = _readSettings();
    if (current == null || settings == null || current.services.isEmpty) {
      return;
    }
    await _restartStreaming(current.services, settings);
  }

  /// Получает список сервисов, доступных на сервере.
  Future<List<String>> _fetchServices() async {
    final server = _server;
    if (server == null) {
      return const <String>[];
    }
    final sshService = ref.read(sshServiceProvider);
    final services = await sshService.fetchServices(server);
    services.sort();
    return services;
  }

  AppSettings? _readSettings() {
    final settings = ref.read(settingsProvider).maybeWhen(
          data: (value) => value,
          orElse: () => null,
        );
    if (settings != null) {
      _cachedSettings = settings;
      _lastInitialLines = settings.initialLogLines;
    }
    return settings ?? _cachedSettings;
  }

  Future<void> _startStreaming(
    List<String> services,
    AppSettings settings,
  ) async {
    if (services.isEmpty) {
      return;
    }
    await _subscription?.cancel();
    final server = _server;
    if (server == null) {
      return;
    }
    final sshService = ref.read(sshServiceProvider);
    final stream = sshService.streamLogs(server, services, settings);

    final current = state.valueOrNull ?? const ServerLogsState();
    state = AsyncValue.data(
      current.copyWith(
        isStreaming: true,
        logs: const <LogEntry>[],
      ),
    );

    _subscription = stream.listen(
      (event) {
        final latest = state.valueOrNull;
        if (latest == null) {
          return;
        }
        final updatedLogs = List<LogEntry>.from(latest.logs)..add(event);
        if (updatedLogs.length > _maxBufferedEntries) {
          updatedLogs.removeRange(
            0,
            updatedLogs.length - _maxBufferedEntries,
          );
        }
        state = AsyncValue.data(
          latest.copyWith(logs: updatedLogs, isStreaming: true),
        );
      },
      onError: (error, stackTrace) {
        state = AsyncValue.error(error, stackTrace);
      },
      onDone: () {
        final latest = state.valueOrNull;
        if (latest != null) {
          state = AsyncValue.data(
            latest.copyWith(isStreaming: false),
          );
        }
      },
      cancelOnError: false,
    );
  }

  Future<void> _restartStreaming(
    List<String> services,
    AppSettings settings,
  ) async {
    await _subscription?.cancel();
    await _startStreaming(services, settings);
  }
}

/// Провайдер, который следит за списком серверов и гарантирует инициализацию
/// фоновых потоков для каждого из них.
final logCollectionBootstrapProvider = Provider<void>((ref) {
  final serversAsync = ref.watch(serverListProvider);
  final servers = serversAsync.value ?? const <ServerConfig>[];
  for (final server in servers) {
    ref.watch(serverLogsProvider(server));
  }
});
