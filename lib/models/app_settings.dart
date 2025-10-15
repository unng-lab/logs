class AppSettings {
  const AppSettings({required this.initialLogLines});

  final int initialLogLines;

  AppSettings copyWith({int? initialLogLines}) {
    return AppSettings(initialLogLines: initialLogLines ?? this.initialLogLines);
  }

  Map<String, dynamic> toJson() {
    return {
      'initialLogLines': initialLogLines,
    };
  }

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
