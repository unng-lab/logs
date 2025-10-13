import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/server_config.dart';
import '../providers/app_providers.dart';
import 'edit_server_screen.dart';
import 'server_detail_screen.dart';
import 'settings_screen.dart';

class ServerListScreen extends ConsumerWidget {
  const ServerListScreen({super.key});

  static const routeName = '/';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serversAsync = ref.watch(serverListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).pushNamed(SettingsScreen.routeName),
          ),
        ],
      ),
      body: serversAsync.when(
        data: (servers) {
          if (servers.isEmpty) {
            return _EmptyState(onAdd: () => _openEditor(context));
          }
          return ListView.separated(
            itemBuilder: (context, index) {
              final server = servers[index];
              return ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(server.name),
                subtitle: Text('${server.username}@${server.host}:${server.port}'),
                onTap: () => _openDetail(context, server),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openEditor(context, server: server),
                ),
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: servers.length,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Failed to load servers: $error'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Add server'),
      ),
    );
  }

  void _openEditor(BuildContext context, {ServerConfig? server}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditServerScreen(server: server),
        fullscreenDialog: true,
      ),
    );
  }

  void _openDetail(BuildContext context, ServerConfig server) {
    Navigator.of(context).pushNamed(
      ServerDetailScreen.routeName,
      arguments: ServerDetailArguments(server: server),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dns_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Добавьте ваш первый сервер',
              style: TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Приложение подключается по SSH, обнаруживает systemd сервисы и показывает журналы в реальном времени.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Добавить сервер'),
            ),
          ],
        ),
      ),
    );
  }
}
