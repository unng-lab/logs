import 'package:flutter_test/flutter_test.dart';

import 'package:logs/models/log_entry.dart';

void main() {
  test('LogEntry defaults isFresh to false when a null value is provided', () {
    final entry = LogEntry(
      timestamp: DateTime.utc(2024, 1, 1),
      message: 'test message',
      severity: LogSeverity.info,
      service: 'ssh.service',
      raw: const <String, dynamic>{},
      receivedAt: DateTime.utc(2024, 1, 1),
      isFresh: null,
    );

    expect(entry.isFresh, isFalse);
  });

  test('copyWith keeps the current freshness flag by default', () {
    final original = LogEntry(
      timestamp: DateTime.utc(2024, 1, 1),
      message: 'original',
      severity: LogSeverity.error,
      service: 'ssh.service',
      raw: const <String, dynamic>{},
      receivedAt: DateTime.utc(2024, 1, 1),
      isFresh: true,
    );

    final copy = original.copyWith();

    expect(copy.isFresh, isTrue);
  });
}
