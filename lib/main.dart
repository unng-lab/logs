import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/app_providers.dart';
import 'screens/server_detail_screen.dart';
import 'screens/server_list_screen.dart';
import 'screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
      ],
      child: const SSHLogsApp(),
    ),
  );
}

class SSHLogsApp extends ConsumerWidget {
  const SSHLogsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'SSH Systemd Logs',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      routes: {
        ServerListScreen.routeName: (_) => const ServerListScreen(),
        SettingsScreen.routeName: (_) => const SettingsScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == ServerDetailScreen.routeName) {
          final args = settings.arguments! as ServerDetailArguments;
          return MaterialPageRoute(
            builder: (_) => ServerDetailScreen(args: args),
          );
        }
        return null;
      },
      initialRoute: ServerListScreen.routeName,
    );
  }
}
