import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logs/repositories/settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsRepository> _createRepository(
    Map<String, Object> initialValues,
  ) async {
    SharedPreferences.setMockInitialValues(initialValues);
    final preferences = await SharedPreferences.getInstance();
    return SettingsRepository(preferences);
  }

  test('returns defaults when no settings are stored', () async {
    final repository = await _createRepository({});

    final settings = await repository.load();

    expect(settings.initialLogLines, 100);
  });

  test('returns defaults when stored JSON is corrupted', () async {
    final repository = await _createRepository({
      'settings': '{invalid json',
    });

    final settings = await repository.load();

    expect(settings.initialLogLines, 100);
  });
}
