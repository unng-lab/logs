import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/log_entry.dart';
import '../models/server_config.dart';
import 'app_providers.dart';

/// Оповещение, которое контроллер может отправить во вью.
class ServerDetailAlert {
  const ServerDetailAlert({
    required this.message,
    required this.id,
    this.isError = false,
  });

  final String message;
  final int id;
  final bool isError;
}

/// Состояние детального экрана сервера.
class ServerDetailState {
  const ServerDetailState({
    this.services = const <String>[],
    this.selectedService,
    this.logs = const <LogEntry>[],
    this.isStreaming = false,
    this.isLoadingServices = true,
    this.alert,
  });

  final List<String> services;
  final String? selectedService;
  final List<LogEntry> logs;
  final bool isStreaming;
  final bool isLoadingServices;
  final ServerDetailAlert? alert;

  ServerDetailState copyWith({
    List<String>? services,
    String? selectedService,
    List<LogEntry>? logs,
    bool? isStreaming,
    bool? isLoadingServices,
    ServerDetailAlert? alert,
    bool clearAlert = false,
  }) {
    return ServerDetailState(
      services: services ?? this.services,
      selectedService: selectedService ?? this.selectedService,
      logs: logs ?? this.logs,
      isStreaming: isStreaming ?? this.isStreaming,
      isLoadingServices: isLoadingServices ?? this.isLoadingServices,
      alert: clearAlert ? null : (alert ?? this.alert),
    );
  }
}

/// Провайдер, управляющий состоянием [ServerDetailScreen].
final serverDetailControllerProvider = AutoDisposeAsyncNotifierProviderFamily<
    ServerDetailController,
    ServerDetailState,
    ServerConfig>(ServerDetailController.new);

class ServerDetailController
    extends AutoDisposeFamilyAsyncNotifier<ServerDetailState, ServerConfig> {
  late ServerConfig _server;
  StreamSubscription<LogEntry>? _subscription;
  int _alertId = 0;
  bool _shouldStream = false;

  @override
  FutureOr<ServerDetailState> build(ServerConfig server) async {
    _server = server;
    ref.onDispose(() => _subscription?.cancel());
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
      final settings = next.valueOrNull;
      final current = state.value;
      if (settings == null ||
          current == null ||
          current.selectedService == null ||
          !_shouldStream) {
        return;
      }
      unawaited(restartStreaming(settings));
    });
    return _loadInitial();
  }

  Future<ServerDetailState> _loadInitial() async {
    try {
      final services =
          await ref.read(sshServiceProvider).fetchServices(_server);
      final selected = _resolveSelectedService(
        services,
        _server.defaultService,
      );
      final state = ServerDetailState(
        services: services,
        selectedService: selected,
        logs: const <LogEntry>[],
        isStreaming: false,
        isLoadingServices: false,
      );
      _shouldStream = selected != null;
      if (_shouldStream) {
        final settings = _readSettings();
        if (settings != null) {
          unawaited(Future.microtask(() => _startStreaming(settings)));
        }
      }
      return state;
    } catch (error, stackTrace) {
      return Future.error(error, stackTrace);
    }
  }

  Future<void> refreshServices() async {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncValue.data(current.copyWith(isLoadingServices: true));
    try {
      final services =
          await ref.read(sshServiceProvider).fetchServices(_server);
      final selected = _resolveSelectedService(
        services,
        current.selectedService ?? _server.defaultService,
      );
      final updated = current.copyWith(
        services: services,
        selectedService: selected,
        isLoadingServices: false,
        clearAlert: true,
      );
      state = AsyncValue.data(updated);
      _shouldStream = selected != null;
      if (_shouldStream) {
        final settings = _readSettings();
        if (settings != null) {
          await restartStreaming(settings);
        }
      }
    } catch (error) {
      final updated = current.copyWith(
        isLoadingServices: false,
        alert:
            _createAlert('Не удалось загрузить сервисы: $error', isError: true),
      );
      state = AsyncValue.data(updated);
    }
  }

  Future<void> selectService(String? service) async {
    final current = state.value;
    if (current == null || service == current.selectedService) {
      return;
    }
    final updatedServer = _server.copyWith(defaultService: service);
    _server = updatedServer;
    await ref.read(serverListProvider.notifier).update(updatedServer);
    state = AsyncValue.data(
      current.copyWith(
        selectedService: service,
        clearAlert: true,
      ),
    );
  }

  Future<void> toggleStreaming() async {
    final current = state.value;
    if (current == null || current.selectedService == null) {
      return;
    }
    if (current.isStreaming) {
      _shouldStream = false;
      await _stopStreaming();
    } else {
      final settings = _readSettings();
      if (settings == null) {
        _emitAlert('Настройки приложения ещё не загружены', isError: true);
        return;
      }
      _shouldStream = true;
      await restartStreaming(settings);
    }
  }

  Future<void> restartStreaming(AppSettings settings) async {
    await _stopStreaming();
    await _startStreaming(settings);
  }

  Future<void> _startStreaming(AppSettings settings) async {
    final current = state.value;
    if (current == null ||
        current.selectedService == null ||
        current.services.isEmpty) {
      return;
    }
    await _subscription?.cancel();
    state = AsyncValue.data(
      current.copyWith(
        logs: const <LogEntry>[],
        isStreaming: true,
        clearAlert: true,
      ),
    );
    final sshService = ref.read(sshServiceProvider);
    final stream = sshService.streamLogs(_server, current.services, settings);
    _subscription = stream.listen(
      (event) {
        final latest = state.value;
        if (latest == null) {
          return;
        }
        final logs = List<LogEntry>.from(latest.logs)..add(event);
        state = AsyncValue.data(latest.copyWith(logs: logs));
      },
      onError: (error, stackTrace) {
        _emitAlert('Ошибка потока логов: $error', isError: true);
        unawaited(_stopStreaming());
      },
      onDone: () {
        unawaited(_stopStreaming());
      },
      cancelOnError: false,
    );
  }

  Future<void> _stopStreaming() async {
    await _subscription?.cancel();
    _subscription = null;
    final current = state.value;
    if (current != null) {
      state = AsyncValue.data(
        current.copyWith(
          isStreaming: false,
        ),
      );
    }
  }

  AppSettings? _readSettings() {
    return ref.read(settingsProvider).maybeWhen(
          data: (value) => value,
          orElse: () => null,
        );
  }

  String? _resolveSelectedService(List<String> services, String? preferred) {
    if (preferred != null && services.contains(preferred)) {
      return preferred;
    }
    if (services.isNotEmpty) {
      return services.first;
    }
    return null;
  }

  void _emitAlert(String message, {bool isError = false}) {
    final current = state.value;
    if (current == null) {
      return;
    }
    state = AsyncValue.data(
      current.copyWith(
        alert: _createAlert(message, isError: isError),
      ),
    );
  }

  ServerDetailAlert _createAlert(String message, {bool isError = false}) {
    _alertId++;
    return ServerDetailAlert(
      message: message,
      id: _alertId,
      isError: isError,
    );
  }

  void clearAlert() {
    final current = state.value;
    if (current == null || current.alert == null) {
      return;
    }
    state = AsyncValue.data(current.copyWith(clearAlert: true));
  }
}
