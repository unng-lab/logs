/// Настройки приложения, влияющие на работу потоков логов.
class AppSettings {
  const AppSettings({required this.initialLogLines});

  final int initialLogLines;

  /// Возвращает копию настроек с изменёнными полями.
  AppSettings copyWith({int? initialLogLines}) {
    return AppSettings(
        initialLogLines: initialLogLines ?? this.initialLogLines);
  }

  /// Сериализует настройки в JSON для хранения.
  Map<String, dynamic> toJson() {
    return {
      'initialLogLines': initialLogLines,
    };
  }

  /// Восстанавливает настройки из JSON, учитывая значения по умолчанию.
  static AppSettings fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const AppSettings(initialLogLines: 100);
    }
    final explicitLines = (json['initialLogLines'] as num?)?.toInt();
    if (explicitLines != null && explicitLines > 0) {
      return AppSettings(initialLogLines: explicitLines);
    }
    // Backwards compatibility with previously stored settings.
    return const AppSettings(initialLogLines: 100);
  }
}
