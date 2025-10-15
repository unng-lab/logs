import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class SettingsRepository {
  SettingsRepository(this._preferences);

  static const _storageKey = 'settings';

  final SharedPreferences _preferences;

  Future<AppSettings> load() async {
    final raw = _preferences.getString(_storageKey);
    if (raw == null) {
      return const AppSettings(initialLogLines: 100);
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return AppSettings.fromJson(decoded);
  }

  Future<void> save(AppSettings settings) async {
    final encoded = jsonEncode(settings.toJson());
    await _preferences.setString(_storageKey, encoded);
  }
}
