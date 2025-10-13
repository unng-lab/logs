import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_config.dart';

class ServerRepository {
  ServerRepository(this._preferences);

  static const _storageKey = 'servers';

  final SharedPreferences _preferences;

  Future<List<ServerConfig>> loadServers() async {
    final raw = _preferences.getString(_storageKey);
    return ServerConfig.decodeList(raw);
  }

  Future<void> saveServers(List<ServerConfig> servers) async {
    final encoded = jsonEncode(servers.map((server) => server.toJson()).toList());
    await _preferences.setString(_storageKey, encoded);
  }
}
