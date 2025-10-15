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
  static const int _minLines = 50;
  static const int _maxLines = 500;
  static const int _step = 50;
  late double _initialLines;

  @override
  void initState() {
    super.initState();
    final clamped = widget.settings.initialLogLines.clamp(_minLines, _maxLines);
    final snapped = ((clamped - _minLines) / _step).round() * _step + _minLines;
    _initialLines = snapped.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(settingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Сколько строк журнала загружать при подключении (по умолчанию 100)?',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Slider(
          value: _initialLines,
          min: _minLines.toDouble(),
          max: _maxLines.toDouble(),
          divisions: (_maxLines - _minLines) ~/ _step,
          label: '${_initialLines.round()} строк',
          onChanged: (value) => setState(() => _initialLines = value),
          onChangeEnd: (value) {
            final snapped =
                (((value - _minLines) / _step).round() * _step + _minLines).clamp(_minLines, _maxLines).toInt();
            setState(() => _initialLines = snapped.toDouble());
            notifier.update(
              widget.settings.copyWith(initialLogLines: snapped),
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          'Текущая глубина: ${_initialLines.round()} строк',
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
