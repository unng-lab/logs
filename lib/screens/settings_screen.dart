import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_settings.dart';
import '../providers/app_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const routeName = '/settings';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: settingsAsync.when(
        data: (settings) => _SettingsForm(settings: settings),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Ошибка загрузки настроек: $error')),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late double _retentionDays;

  @override
  void initState() {
    super.initState();
    _retentionDays = widget.settings.logRetentionDays.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(settingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Сколько дней хранить логи при подключении (по умолчанию 7)?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Slider(
          value: _retentionDays,
          min: 1,
          max: 30,
          divisions: 29,
          label: '${_retentionDays.round()} дней',
          onChanged: (value) => setState(() => _retentionDays = value),
          onChangeEnd: (value) => notifier.update(
            widget.settings.copyWith(logRetentionDays: value.round()),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Текущая глубина: ${_retentionDays.round()} дней',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        const Text(
          'Настройки сохраняются локально на устройстве и применяются ко всем серверам.',
        ),
      ],
    );
  }
}
