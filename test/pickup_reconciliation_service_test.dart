import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_app/services/pickup_reconciliation_service.dart';

void main() {
  final service = PickupReconciliationService.instance;

  tearDown(() {
    service.stop();
    service.runOnce = () async {};
  });

  test('start runs the pass immediately and then on each interval', () {
    fakeAsync((async) {
      var calls = 0;
      service.runOnce = () async {
        calls++;
      };
      service.start(interval: const Duration(seconds: 45));
      expect(calls, 1);
      async.elapse(const Duration(seconds: 45));
      expect(calls, 2);
      async.elapse(const Duration(seconds: 90));
      expect(calls, 4);
      service.stop();
    });
  });

  test('start is idempotent and does not create a second timer', () {
    fakeAsync((async) {
      var calls = 0;
      service.runOnce = () async {
        calls++;
      };
      service.start(interval: const Duration(seconds: 45));
      service.start(interval: const Duration(seconds: 45));
      service.start(interval: const Duration(seconds: 45));
      expect(calls, 1);
      async.elapse(const Duration(seconds: 45));
      // With duplicate timers this would be 4; an idempotent start yields 2.
      expect(calls, 2);
      service.stop();
    });
  });

  test('stop cancels the periodic timer and isRunning reflects state', () {
    fakeAsync((async) {
      var calls = 0;
      service.runOnce = () async {
        calls++;
      };
      expect(service.isRunning, isFalse);
      service.start();
      expect(service.isRunning, isTrue);
      service.stop();
      expect(service.isRunning, isFalse);
      async.elapse(const Duration(minutes: 5));
      expect(calls, 1); // Only the initial immediate pass ran.
    });
  });
}
