import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/log_entry.dart';
import '../models/server_config.dart';
import 'app_providers.dart';
import 'server_logs_provider.dart';
import '../services/ssh_service.dart';

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
  static const Object _sentinel = Object();

  const ServerDetailState({
    this.services = const <String>[],
    this.selectedService,
    this.logs = const <LogEntry>[],
    this.isStreaming = false,
    this.isLoadingServices = true,
    this.activeServiceAction,
    this.alert,
  });

  final List<String> services;
  final String? selectedService;
  final List<LogEntry> logs;
  final bool isStreaming;
  final bool isLoadingServices;
  final ServiceAction? activeServiceAction;
  final ServerDetailAlert? alert;

  ServerDetailState copyWith({
    List<String>? services,
    Object? selectedService = _sentinel,
    List<LogEntry>? logs,
    bool? isStreaming,
    bool? isLoadingServices,
    Object? activeServiceAction = _sentinel,
    ServerDetailAlert? alert,
    bool clearAlert = false,
  }) {
    final resolvedSelectedService = selectedService == _sentinel
        ? this.selectedService
        : selectedService as String?;
    final resolvedActiveServiceAction = activeServiceAction == _sentinel
        ? this.activeServiceAction
        : activeServiceAction as ServiceAction?;
    return ServerDetailState(
      services: services ?? this.services,
      selectedService: resolvedSelectedService,
      logs: logs ?? this.logs,
      isStreaming: isStreaming ?? this.isStreaming,
      isLoadingServices: isLoadingServices ?? this.isLoadingServices,
      activeServiceAction: resolvedActiveServiceAction,
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
  int _alertId = 0;
  String? _userSelectedService;

  @override
  FutureOr<ServerDetailState> build(ServerConfig server) async {
    _server = server;
    ref.listen<AsyncValue<ServerLogsState>>(serverLogsProvider(server),
        (previous, next) {
      if (next.hasError && next.error != null) {
        _emitAlert('Ошибка потока логов: ${next.error}', isError: true);
        return;
      }
      final data = next.valueOrNull;
      if (data == null) {
        if (next.isLoading) {
          state = const AsyncValue.loading();
        }
        return;
      }
      final current = state.valueOrNull;
      final selected = _resolveSelectedService(
        data.services,
        _userSelectedService ??
            current?.selectedService ??
            _server.defaultService,
      );
      _syncUserSelectedService(data.services, selected);
      final updated = (current ?? const ServerDetailState()).copyWith(
        services: data.services,
        selectedService: selected,
        logs: data.logs,
        isStreaming: data.isStreaming,
        isLoadingServices: data.isLoadingServices,
        clearAlert: true,
      );
      state = AsyncValue.data(updated);
    });

    final backgroundState = await ref.watch(serverLogsProvider(server).future);
    final selected = _resolveSelectedService(
      backgroundState.services,
      _userSelectedService ?? server.defaultService,
    );
    _syncUserSelectedService(backgroundState.services, selected);
    return ServerDetailState(
      services: backgroundState.services,
      selectedService: selected,
      logs: backgroundState.logs,
      isStreaming: backgroundState.isStreaming,
      isLoadingServices: backgroundState.isLoadingServices,
    );
  }

  Future<void> refreshServices() async {
    await ref.read(serverLogsProvider(_server).notifier).refreshServices();
  }

  Future<void> selectService(String? service) async {
    final current = state.value;
    if (current == null || service == current.selectedService) {
      return;
    }
    _userSelectedService = service;
    state = AsyncValue.data(
      current.copyWith(
        selectedService: service,
        clearAlert: true,
      ),
    );
    final updatedServer = _server.copyWith(defaultService: service);
    _server = updatedServer;
    await ref.read(serverListProvider.notifier).update(updatedServer);
  }

  Future<void> toggleStreaming() async {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    await ref.read(serverLogsProvider(_server).notifier).restart();
  }

  Future<void> restartSelectedService() async {
    await _runServiceAction(
      action: ServiceAction.restart,
      onPerform: (sshService, service) async {
        await sshService.restartService(_server, service);
        await ref.read(serverLogsProvider(_server).notifier).restart();
        return 'Сервис $service перезапущен';
      },
    );
  }

  Future<void> startSelectedService() async {
    await _runServiceAction(
      action: ServiceAction.start,
      onPerform: (sshService, service) async {
        await sshService.startService(_server, service);
        await ref.read(serverLogsProvider(_server).notifier).restart();
        return 'Сервис $service запущен';
      },
    );
  }

  Future<void> stopSelectedService() async {
    await _runServiceAction(
      action: ServiceAction.stop,
      onPerform: (sshService, service) async {
        await sshService.stopService(_server, service);
        await ref.read(serverLogsProvider(_server).notifier).restart();
        return 'Сервис $service остановлен';
      },
    );
  }

  Future<void> fetchSelectedServiceStatus() async {
    await _runServiceAction(
      action: ServiceAction.status,
      onPerform: (sshService, service) async {
        final status = await sshService.fetchServiceStatus(_server, service);
        return 'Статус сервиса $service: $status';
      },
    );
  }

  Future<void> _runServiceAction({
    required ServiceAction action,
    required Future<String> Function(SSHService sshService, String service)
        onPerform,
  }) async {
    final current = state.valueOrNull;
    final service = current?.selectedService;
    if (current == null || service == null) {
      return;
    }

    state = AsyncValue.data(
      current.copyWith(
        activeServiceAction: action,
        clearAlert: true,
      ),
    );

    try {
      final sshService = ref.read(sshServiceProvider);
      final message = await onPerform(sshService, service);

      final latest = state.valueOrNull ?? current;
      state = AsyncValue.data(
        latest.copyWith(
          activeServiceAction: null,
          alert: _createAlert(message),
        ),
      );
    } catch (error) {
      final latest = state.valueOrNull ?? current;
      state = AsyncValue.data(
        latest.copyWith(
          activeServiceAction: null,
          alert: _createAlert(
            'Не удалось выполнить действие: $error',
            isError: true,
          ),
        ),
      );
    }
  }

  String? _resolveSelectedService(List<String> services, String? preferred) {
    if (preferred == null) {
      return null;
    }
    if (services.contains(preferred)) {
      return preferred;
    }
    if (services.isNotEmpty) {
      return services.first;
    }
    return null;
  }

  void _syncUserSelectedService(List<String> services, String? resolved) {
    final userSelection = _userSelectedService;
    if (userSelection != null && !services.contains(userSelection)) {
      _userSelectedService = resolved;
      return;
    }
    if (userSelection == null && resolved != null) {
      _userSelectedService = resolved;
    }
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

enum ServiceAction { status, start, restart, stop }
