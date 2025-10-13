class AppSettings {
  const AppSettings({required this.logRetentionDays});

  final int logRetentionDays;

  AppSettings copyWith({int? logRetentionDays}) {
    return AppSettings(logRetentionDays: logRetentionDays ?? this.logRetentionDays);
  }

  Map<String, dynamic> toJson() {
    return {
      'logRetentionDays': logRetentionDays,
    };
  }

  static AppSettings fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const AppSettings(logRetentionDays: 7);
    }
    return AppSettings(
      logRetentionDays: (json['logRetentionDays'] as num?)?.toInt() ?? 7,
    );
  }
}
