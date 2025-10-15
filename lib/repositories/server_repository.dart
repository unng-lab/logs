import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_config.dart';

/// Репозиторий для сохранения и загрузки конфигураций серверов.
class ServerRepository {
  ServerRepository(this._preferences);

  static const _storageKey = 'servers';

  final SharedPreferences _preferences;

  /// Возвращает список серверов из локального хранилища.
  Future<List<ServerConfig>> loadServers() async {
    final raw = _preferences.getString(_storageKey);
    return ServerConfig.decodeList(raw);
  }

  /// Сохраняет текущий список серверов в локальное хранилище.
  Future<void> saveServers(List<ServerConfig> servers) async {
    final encoded = jsonEncode(servers.map((server) => server.toJson()).toList());
    await _preferences.setString(_storageKey, encoded);
  }
}
