import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:logs/models/server_config.dart';
import 'package:logs/providers/app_providers.dart';
import 'package:logs/screens/server_list_screen.dart';

void main() {
  testWidgets(
    'updating status of one server does not rebuild other tiles',
    (tester) async {
      final server1 = ServerConfig(
        id: 'server-1',
        name: 'Server 1',
        host: '192.168.0.1',
        username: 'user1',
      );
      final server2 = ServerConfig(
        id: 'server-2',
        name: 'Server 2',
        host: '192.168.0.2',
        username: 'user2',
      );

      final initialStatus = <String, bool>{
        server1.id: true,
        server2.id: true,
      };
      final statusBuildCounts = <String, int>{
        server1.id: 0,
        server2.id: 0,
      };
      final statusStateProvider =
          StateProvider.family<bool, String>((ref, id) => initialStatus[id]!);

      final container = ProviderContainer(
        overrides: [
          serverStatusProvider.overrideWithProvider(
            (server) => AutoDisposeFutureProvider<bool>((ref) async {
              statusBuildCounts[server.id] =
                  (statusBuildCounts[server.id] ?? 0) + 1;
              return ref.watch(statusStateProvider(server.id));
            }),
          ),
          serverLogRateProvider.overrideWithProvider(
            (server) => AutoDisposeStreamProvider<double>((ref) {
              return const Stream<double>.empty();
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ListView(
                children: [
                  ServerListTile(
                    key: ValueKey(server1.id),
                    server: server1,
                    onOpenDetail: () {},
                    onOpenEditor: () {},
                  ),
                  ServerListTile(
                    key: ValueKey(server2.id),
                    server: server2,
                    onOpenDetail: () {},
                    onOpenEditor: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(statusBuildCounts[server1.id], 1);
      expect(statusBuildCounts[server2.id], 1);

      container.read(statusStateProvider(server1.id).notifier).state = false;

      await tester.pump();
      await tester.pump();

      expect(statusBuildCounts[server1.id], 2);
      expect(statusBuildCounts[server2.id], 1);
      expect(find.text('Отключен'), findsOneWidget);
      expect(find.text('Онлайн'), findsOneWidget);
    },
  );
}
