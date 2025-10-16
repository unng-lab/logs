import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logs/models/log_entry.dart';
import 'package:logs/models/server_config.dart';
import 'package:logs/providers/app_providers.dart';
import 'package:logs/providers/server_detail_controller.dart';
import 'package:logs/screens/server_detail_screen.dart';

void main() {
  testWidgets('shows alert snackbars and clears them', (tester) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    final server = ServerConfig(
      id: 'test',
      name: 'Server',
      host: 'localhost',
      username: 'root',
      port: 22,
    );

    final controller = _FakeServerDetailController(
      const ServerDetailState(
        services: <String>['nginx'],
        selectedService: 'nginx',
        logs: <LogEntry>[],
        isLoadingServices: false,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          serverDetailControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp(
          home: ServerDetailScreen(
            args: ServerDetailArguments(server: server),
          ),
        ),
      ),
    );

    expect(find.byType(SnackBar), findsNothing);

    controller.emitAlert('Test alert');
    await tester.pump();
    await tester.pump();

    expect(find.text('Test alert'), findsOneWidget);
    expect(controller.clearAlertCount, 1);
  });

  testWidgets('keeps "Все логи" selected after choosing it', (tester) async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final preferences = await SharedPreferences.getInstance();

    final server = ServerConfig(
      id: 'test',
      name: 'Server',
      host: 'localhost',
      username: 'root',
      port: 22,
    );

    final controller = _FakeServerDetailController(
      const ServerDetailState(
        services: <String>['api', 'billing'],
        selectedService: 'api',
        logs: <LogEntry>[],
        isLoadingServices: false,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          serverDetailControllerProvider.overrideWith(() => controller),
        ],
        child: MaterialApp(
          home: ServerDetailScreen(
            args: ServerDetailArguments(server: server),
          ),
        ),
      ),
    );

    final dropdownFinder = find.byType(DropdownButtonFormField<String?>);
    expect(dropdownFinder, findsOneWidget);

    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Все логи').last);
    await tester.pumpAndSettle();

    final selectedTextFinder = find.descendant(
      of: dropdownFinder,
      matching: find.text('Все логи'),
    );
    expect(selectedTextFinder, findsOneWidget);
  });
}

class _FakeServerDetailController extends ServerDetailController {
  _FakeServerDetailController(this._initialState);

  final ServerDetailState _initialState;
  int clearAlertCount = 0;
  int _alertCounter = 0;

  @override
  FutureOr<ServerDetailState> build(ServerConfig arg) => _initialState;

  @override
  void clearAlert() {
    clearAlertCount++;
    final current = state.value;
    if (current != null) {
      state = AsyncValue.data(current.copyWith(clearAlert: true));
    }
  }

  void emitAlert(String message) {
    final current = state.value ?? _initialState;
    _alertCounter++;
    state = AsyncValue.data(
      current.copyWith(
        alert: ServerDetailAlert(
          message: message,
          id: _alertCounter,
        ),
      ),
    );
  }

  @override
  Future<void> selectService(String? service) async {
    final current = state.value ?? _initialState;
    if (current.selectedService == service) {
      return;
    }
    state = AsyncValue.data(
      current.copyWith(
        selectedService: service,
        clearAlert: true,
      ),
    );
  }
}
