import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_app/engines/order_scheduling_gate.dart';

void main() {
  group('OrderSchedulingGate', () {
    test(
      'treats verified weight as eligible for scheduling when staff is assigned',
      () {
        final order = {
          'paymentStatus': 'Verified',
          'assignedTo': 'staff-1',
          'weightStatus': 'verified',
          'actualWeight': 12.5,
        };

        expect(OrderSchedulingGate.isEligible(order), isTrue);
      },
    );

    test('requires explicit verified weight before scheduling', () {
      final order = {
        'paymentStatus': 'Verified',
        'assignedTo': 'staff-1',
        'weightStatus': 'submitted',
      };

      expect(OrderSchedulingGate.isEligible(order), isFalse);
    });

    test(
      'rejects legacy or missing actual weight instead of using declared weight',
      () {
        expect(
          OrderSchedulingGate.isEligible({
            'paymentStatus': 'Verified',
            'assignedTo': 'staff-1',
            'weightStatus': null,
            'weight': 10.0,
          }),
          isFalse,
        );
      },
    );

    test('requires verified payment even when actual weight is verified', () {
      expect(
        OrderSchedulingGate.isEligible({
          'paymentStatus': 'Pending Verification',
          'assignedTo': 'staff-1',
          'weightStatus': 'verified',
          'actualWeight': 9.82,
        }),
        isFalse,
      );
    });
  });
}
