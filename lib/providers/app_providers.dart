import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/server_config.dart';
import '../repositories/server_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/ssh_service.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences has not been initialized');
});

final serverRepositoryProvider = Provider<ServerRepository>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider);
  return ServerRepository(preferences);
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final preferences = ref.watch(sharedPreferencesProvider);
  return SettingsRepository(preferences);
});

final sshServiceProvider = Provider<SSHService>((ref) => SSHService());

final serverStatusProvider = AutoDisposeFutureProvider.family<bool, ServerConfig>((ref, server) {
  final service = ref.watch(sshServiceProvider);
  return service.checkConnection(server);
});

final serverListProvider = StateNotifierProvider<ServerListNotifier, AsyncValue<List<ServerConfig>>>(
  (ref) => ServerListNotifier(ref.watch(serverRepositoryProvider)),
);

final settingsProvider = StateNotifierProvider<SettingsNotifier, AsyncValue<AppSettings>>(
  (ref) => SettingsNotifier(ref.watch(settingsRepositoryProvider)),
);

class ServerListNotifier extends StateNotifier<AsyncValue<List<ServerConfig>>> {
  ServerListNotifier(this._repository) : super(const AsyncValue.loading()) {
    _load();
  }

  final ServerRepository _repository;

  Future<void> _load() async {
    try {
      final servers = await _repository.loadServers();
      state = AsyncValue.data(servers);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> add(ServerConfig server) async {
    final current = state.value ?? <ServerConfig>[];
    final updated = [...current, server];
    state = AsyncValue.data(updated);
    await _repository.saveServers(updated);
  }

  Future<void> update(ServerConfig server) async {
    final current = state.value ?? <ServerConfig>[];
    final index = current.indexWhere((element) => element.id == server.id);
    if (index == -1) {
      return;
    }
    final updated = [...current];
    updated[index] = server;
    state = AsyncValue.data(updated);
    await _repository.saveServers(updated);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? <ServerConfig>[];
    final updated = current.where((element) => element.id != id).toList();
    state = AsyncValue.data(updated);
    await _repository.saveServers(updated);
  }
}

class SettingsNotifier extends StateNotifier<AsyncValue<AppSettings>> {
  SettingsNotifier(this._repository) : super(const AsyncValue.loading()) {
    _load();
  }

  final SettingsRepository _repository;

  Future<void> _load() async {
    try {
      final settings = await _repository.load();
      state = AsyncValue.data(settings);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> update(AppSettings settings) async {
    state = AsyncValue.data(settings);
    await _repository.save(settings);
  }
}
