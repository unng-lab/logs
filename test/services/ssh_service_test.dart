import 'package:flutter_test/flutter_test.dart';
import 'package:logs/services/ssh_service.dart';

void main() {
  group('SSHService CPU parser', () {
    final service = SSHService();

    test('parses standard top output', () {
      const topOutput =
          '%Cpu(s): 12.0 us, 5.0 sy, 0.0 ni, 80.0 id, 3.0 wa, 0.0 hi, 0.0 si, 0.0 st';

      final usage = service.debugParseCpuUsage(topOutput);

      expect(usage, closeTo(20.0, 0.1));
    });

    test('parses busybox style CPU output', () {
      const busyboxOutput =
          'CPU:  1% usr  2% sys  0% nic 97% idle  0% io  0% irq  0% sirq';

      final usage = service.debugParseCpuUsage(busyboxOutput);

      expect(usage, closeTo(3.0, 0.1));
    });

    test('returns null when no numbers present', () {
      const emptyOutput = 'unexpected output';

      final usage = service.debugParseCpuUsage(emptyOutput);

      expect(usage, isNull);
    });
  });
}
