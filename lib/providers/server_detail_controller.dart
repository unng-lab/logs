import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../models/log_entry.dart';
import '../models/server_config.dart';
import '../services/ssh_service.dart';
import 'app_providers.dart';

class ServerDetailState {
  const ServerDetailState({
    required this.services,
    required this.selectedService,
    required this.logs,
    required this.isStreaming,
    required this.isLoadingServices,
    required this.errorMessage,
  });

  factory ServerDetailState.initial() {
    return const ServerDetailState(
      services: <String>[],
      selectedService: null,
      logs: <LogEntry>[],
      isStreaming: false,
      isLoadingServices: true,
      errorMessage: null,
    );
  }

  final List<String> services;
  final String? selectedService;
  final List<LogEntry> logs;
  final bool isStreaming;
  final bool isLoadingServices;
  final String? errorMessage;

  ServerDetailState copyWith({
    List<String>? services,
    String? selectedService,
    List<LogEntry>? logs,
    bool? isStreaming,
    bool? isLoadingServices,
    String? errorMessage,
    bool removeError = false,
  }) {
    return ServerDetailState(
      services: services ?? this.services,
      selectedService: selectedService ?? this.selectedService,
      logs: logs ?? this.logs,
      isStreaming: isStreaming ?? this.isStreaming,
      isLoadingServices: isLoadingServices ?? this.isLoadingServices,
      errorMessage: removeError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final serverDetailControllerProvider =
    AutoDisposeAsyncNotifierProviderFamily<ServerDetailController, ServerDetailState, ServerConfig>(
  ServerDetailController.new,
);

class ServerDetailController extends AutoDisposeAsyncNotifier<ServerDetailState> {
  StreamSubscription<LogEntry>? _subscription;
  late ServerConfig _server;

  SSHService get _sshService => ref.read(sshServiceProvider);

  @override
  Future<ServerDetailState> build(ServerConfig server) async {
    _server = server;
    ref.onDispose(() {
      _subscription?.cancel();
    });

    final settings = await ref.watch(settingsProvider.future);
    try {
      final services = await _sshService.fetchServices(server);
      final selected = _resolveSelectedService(services);
      final nextState = ServerDetailState.initial().copyWith(
        services: services,
        selectedService: selected,
        isLoadingServices: false,
        removeError: true,
        logs: const <LogEntry>[],
        isStreaming: false,
      );
      Future.microtask(() {
        if (selected != null) {
          unawaited(_restartStream(settings));
        }
      });
      return nextState;
    } catch (error) {
      return ServerDetailState.initial().copyWith(
        isLoadingServices: false,
        errorMessage: 'Не удалось загрузить сервисы: $error',
      );
    }
  }

  Future<void> refreshServices() async {
    final current = state.valueOrNull ?? ServerDetailState.initial();
    state = AsyncValue.data(
      current.copyWith(
        isLoadingServices: true,
        removeError: true,
      ),
    );
    try {
      final services = await _sshService.fetchServices(_server);
      final selected = _resolveSelectedService(
        services,
        preferred: current.selectedService,
      );
      state = AsyncValue.data(
        current.copyWith(
          services: services,
          selectedService: selected,
          logs: const <LogEntry>[],
          isLoadingServices: false,
          isStreaming: false,
          removeError: true,
        ),
      );
      if (selected != null) {
        final settings = await ref.watch(settingsProvider.future);
        await _restartStream(settings);
      } else {
        await _stopStreaming(clearLogs: false);
      }
    } catch (error) {
      state = AsyncValue.data(
        current.copyWith(
          isLoadingServices: false,
          errorMessage: 'Не удалось загрузить сервисы: $error',
        ),
      );
    }
  }

  Future<void> selectService(String? service) async {
    final current = state.valueOrNull;
    if (current == null || current.selectedService == service) {
      return;
    }
    state = AsyncValue.data(
      current.copyWith(
        selectedService: service,
        logs: const <LogEntry>[],
        removeError: true,
        isStreaming: false,
      ),
    );
    await _stopStreaming();
    if (service != null) {
      final updated = _server.copyWith(defaultService: service);
      _server = updated;
      await ref.read(serverListProvider.notifier).update(updated);
      final settings = await ref.watch(settingsProvider.future);
      await _restartStream(settings);
    }
  }

  Future<void> toggleStreaming() async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    if (current.isStreaming) {
      await _stopStreaming();
      state = AsyncValue.data(
        current.copyWith(isStreaming: false),
      );
      return;
    }
    final settings = await ref.watch(settingsProvider.future);
    await _restartStream(settings);
  }

  Future<void> _restartStream(AppSettings settings) async {
    await _stopStreaming(clearLogs: true);
    final current = state.valueOrNull;
    if (current == null || current.selectedService == null || current.services.isEmpty) {
      return;
    }
    state = AsyncValue.data(
      current.copyWith(
        logs: const <LogEntry>[],
        isStreaming: false,
        removeError: true,
      ),
    );
    final stream = _sshService.streamLogs(_server, current.services, settings);
    _subscription = stream.listen(
      (event) {
        final latest = state.valueOrNull;
        if (latest == null) {
          return;
        }
        final logs = [...latest.logs, event];
        state = AsyncValue.data(
          latest.copyWith(
            logs: logs,
            isStreaming: true,
          ),
        );
      },
      onError: (error, stackTrace) {
        final latest = state.valueOrNull;
        if (latest == null) {
          return;
        }
        state = AsyncValue.data(
          latest.copyWith(
            isStreaming: false,
            errorMessage: 'Ошибка потока логов: $error',
          ),
        );
      },
      onDone: () {
        final latest = state.valueOrNull;
        if (latest == null) {
          return;
        }
        state = AsyncValue.data(
          latest.copyWith(isStreaming: false),
        );
      },
    );
  }

  Future<void> _stopStreaming({bool clearLogs = true}) async {
    await _subscription?.cancel();
    _subscription = null;
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    state = AsyncValue.data(
      current.copyWith(
        isStreaming: false,
        logs: clearLogs ? const <LogEntry>[] : current.logs,
      ),
    );
  }

  String? _resolveSelectedService(List<String> services, {String? preferred}) {
    if (services.isEmpty) {
      return null;
    }
    final defaultService = preferred ?? _server.defaultService;
    if (defaultService != null && services.contains(defaultService)) {
      return defaultService;
    }
    return services.first;
  }
}
