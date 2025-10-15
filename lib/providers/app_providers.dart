import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/server_config.dart';
import '../repositories/server_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/ssh_service.dart';

/// Провайдер для доступа к экземпляру SharedPreferences, инициализируется
/// во время запуска приложения и переопределяется в [main].
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences has not been initialized');
});

/// Провайдер репозитория серверов, инкапсулирующего работу с хранилищем.
final serverRepositoryProvider = Provider<ServerRepository>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider);
  return ServerRepository(preferences);
});

/// Провайдер репозитория настроек приложения.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider);
  return SettingsRepository(preferences);
});

/// Провайдер сервиса работы по SSH.
final sshServiceProvider = Provider<SSHService>((ref) => SSHService());

/// Асинхронно проверяет доступность сервера, автоматически освобождая ресурсы
/// при отсутствии слушателей.
final serverStatusProvider = AutoDisposeFutureProvider.family<bool, ServerConfig>((ref, server) {
  final service = ref.watch(sshServiceProvider);
  return service.checkConnection(server);
});

/// Потоковое значение количества строк журнала в секунду. Периодически
/// запрашивает метрику у сервера, чтобы обновлять показания в реальном времени.
final serverLogRateProvider =
    AutoDisposeStreamProvider.family<double, ServerConfig>((ref, server) {
  final service = ref.watch(sshServiceProvider);
  final controller = StreamController<double>();
  Timer? timer;
  var isFetching = false;

  /// Выполняет запрос скорости логов и публикует результат в поток.
  Future<void> fetch() async {
    if (isFetching || controller.isClosed) {
      return;
    }
    isFetching = true;
    try {
      // Считываем текущую скорость поступления записей журнала.
      final rate = await service.fetchLogRate(server);
      if (!controller.isClosed) {
        controller.add(rate);
      }
    } catch (error, stackTrace) {
      // Пробрасываем ошибку в поток, чтобы UI мог отреагировать.
      if (!controller.isClosed) {
        controller.addError(error, stackTrace);
      }
    } finally {
      isFetching = false;
    }
  }

  // Выполняем мгновенный первый запрос, чтобы пользователь сразу увидел данные.
  fetch();

  // Периодически обновляем показатель каждые несколько секунд.
  timer = Timer.periodic(const Duration(seconds: 3), (_) {
    fetch();
  });

  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Провайдер, выдающий список серверов и управляющий изменениями через
/// [ServerListNotifier].
final serverListProvider = StateNotifierProvider<ServerListNotifier, AsyncValue<List<ServerConfig>>>(
  (ref) => ServerListNotifier(ref.watch(serverRepositoryProvider)),
);

/// Провайдер настроек приложения, связанных с параметрами потоков логов.
final settingsProvider = StateNotifierProvider<SettingsNotifier, AsyncValue<AppSettings>>(
  (ref) => SettingsNotifier(ref.watch(settingsRepositoryProvider)),
);

class ServerListNotifier extends StateNotifier<AsyncValue<List<ServerConfig>>> {
  /// Управляет состоянием списка серверов и взаимодействует с хранилищем.
  ServerListNotifier(this._repository) : super(const AsyncValue.loading()) {
    // Сразу загружаем сохранённые данные при создании.
    _load();
  }

  final ServerRepository _repository;

  /// Загружает сохранённый список серверов из репозитория.
  Future<void> _load() async {
    try {
      // Читаем сохранённые конфигурации и публикуем их в виде успешного состояния.
      final servers = await _repository.loadServers();
      state = AsyncValue.data(servers);
    } catch (error, stackTrace) {
      // В случае ошибки сохраняем стек трейс, чтобы UI показал причину.
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Добавляет новый сервер в список и сохраняет изменения.
  Future<void> add(ServerConfig server) async {
    final current = state.value ?? <ServerConfig>[];
    final updated = [...current, server];
    // Сначала обновляем состояние, чтобы UI реагировал мгновенно.
    state = AsyncValue.data(updated);
    await _repository.saveServers(updated);
  }

  /// Обновляет существующий сервер по идентификатору.
  Future<void> update(ServerConfig server) async {
    final current = state.value ?? <ServerConfig>[];
    final index = current.indexWhere((element) => element.id == server.id);
    if (index == -1) {
      return;
    }
    final updated = [...current];
    updated[index] = server;
    // Публикуем обновлённый список и только потом синхронизируем хранилище.
    state = AsyncValue.data(updated);
    await _repository.saveServers(updated);
  }

  /// Удаляет сервер и синхронизирует изменения с хранилищем.
  Future<void> remove(String id) async {
    final current = state.value ?? <ServerConfig>[];
    final updated = current.where((element) => element.id != id).toList();
    state = AsyncValue.data(updated);
    await _repository.saveServers(updated);
  }
}

class SettingsNotifier extends StateNotifier<AsyncValue<AppSettings>> {
  /// Управляет состоянием пользовательских настроек приложения.
  SettingsNotifier(this._repository) : super(const AsyncValue.loading()) {
    // Читаем сохранённые настройки сразу после создания экземпляра.
    _load();
  }

  final SettingsRepository _repository;

  /// Загружает настройки из репозитория при инициализации.
  Future<void> _load() async {
    try {
      // Пробуем получить настройки из хранилища и обновить состояние.
      final settings = await _repository.load();
      state = AsyncValue.data(settings);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Сохраняет новые настройки и обновляет состояние провайдера.
  Future<void> update(AppSettings settings) async {
    state = AsyncValue.data(settings);
    await _repository.save(settings);
  }
}
