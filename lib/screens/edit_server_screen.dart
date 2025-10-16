import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/server_config.dart';
import '../providers/app_providers.dart';

/// Экран создания или редактирования конфигурации сервера.
class EditServerScreen extends ConsumerStatefulWidget {
  const EditServerScreen({super.key, this.server});

  final ServerConfig? server;

  @override
  ConsumerState<EditServerScreen> createState() => _EditServerScreenState();
}

/// Содержит состояние формы редактирования сервера и связанные контроллеры.
class _EditServerScreenState extends ConsumerState<EditServerScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _privateKeyController;
  late final TextEditingController _passphraseController;
  late final TextEditingController _defaultServiceController;

  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;

  /// Заполняет поля формы данными сервера или значениями по умолчанию.
  @override
  void initState() {
    super.initState();
    final server = widget.server;
    _nameController =
        TextEditingController(text: server?.name ?? 'Новый сервер');
    _hostController = TextEditingController(text: server?.host ?? '');
    _portController =
        TextEditingController(text: (server?.port ?? 22).toString());
    _usernameController = TextEditingController(text: server?.username ?? '');
    _passwordController = TextEditingController(text: server?.password ?? '');
    _privateKeyController =
        TextEditingController(text: server?.privateKey ?? '');
    _passphraseController =
        TextEditingController(text: server?.passphrase ?? '');
    _defaultServiceController =
        TextEditingController(text: server?.defaultService ?? '');
  }

  /// Освобождает ресурсы контроллеров при закрытии экрана.
  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _passphraseController.dispose();
    _defaultServiceController.dispose();
    super.dispose();
  }

  /// Строит форму редактирования с валидацией полей.
  @override
  Widget build(BuildContext context) {
    final isEditing = widget.server != null;
    final serversAsync = ref.watch(serverListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Редактировать сервер' : 'Новый сервер'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed:
                  serversAsync.hasValue ? () => _deleteServer(context) : null,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Название'),
              validator: (value) =>
                  value == null || value.isEmpty ? 'Введите название' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _hostController,
              decoration: const InputDecoration(labelText: 'Хост или IP'),
              keyboardType: TextInputType.url,
              validator: (value) => value == null || value.isEmpty
                  ? 'Введите адрес сервера'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _portController,
              decoration: const InputDecoration(labelText: 'SSH порт'),
              keyboardType: TextInputType.number,
              validator: (value) {
                final parsed = int.tryParse(value ?? '');
                if (parsed == null || parsed <= 0) {
                  return 'Укажите корректный порт';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Пользователь'),
              validator: (value) => value == null || value.isEmpty
                  ? 'Введите пользователя'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Пароль',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              obscureText: _obscurePassword,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _privateKeyController,
              decoration: const InputDecoration(
                labelText: 'Приватный ключ (PEM)',
                alignLabelWithHint: true,
              ),
              maxLines: 6,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passphraseController,
              decoration: const InputDecoration(
                  labelText: 'Пароль к ключу (если есть)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _defaultServiceController,
              decoration:
                  const InputDecoration(labelText: 'Сервис по умолчанию'),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: serversAsync.isLoading ? null : () => _save(context),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  /// Сохраняет изменения и обновляет список серверов через провайдер.
  Future<void> _save(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final notifier = ref.read(serverListProvider.notifier);
    // Формируем объект конфигурации, подставляя значения из формы.
    final server = (widget.server ??
            ServerConfig(
              name: _nameController.text.trim(),
              host: _hostController.text.trim(),
              port: int.tryParse(_portController.text.trim()) ?? 22,
              username: _usernameController.text.trim(),
            ))
        .copyWith(
      name: _nameController.text.trim(),
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 22,
      username: _usernameController.text.trim(),
      password:
          _passwordController.text.isEmpty ? null : _passwordController.text,
      privateKey: _privateKeyController.text.isEmpty
          ? null
          : _privateKeyController.text,
      passphrase: _passphraseController.text.isEmpty
          ? null
          : _passphraseController.text,
      defaultService: _defaultServiceController.text.isEmpty
          ? null
          : _defaultServiceController.text,
    );

    if (widget.server == null) {
      await notifier.add(server);
    } else {
      await notifier.update(server);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Запрашивает подтверждение и удаляет сервер при согласии пользователя.
  Future<void> _deleteServer(BuildContext context) async {
    final server = widget.server;
    if (server == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сервер?'),
        content: Text('Вы действительно хотите удалить ${server.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(serverListProvider.notifier).remove(server.id);
      Navigator.of(context).pop();
    }
  }
}
