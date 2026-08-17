import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_app/models/delivery_request_model.dart';

void main() {
  group('DeliveryRequestModel', () {
    test('marks active request states as active', () {
      final states = [
        'requested',
        'queued',
        'assigned',
        'out_for_delivery',
      ];

      for (final state in states) {
        final request = DeliveryRequestModel(
          orderId: 'order-1',
          customerId: 'user-1',
          status: state,
          source: 'customer',
          requestedAt: DateTime.now(),
          deadlineAt: DateTime.now().add(const Duration(days: 2)),
        );

        expect(request.isActive, isTrue);
        expect(request.isTerminal, isFalse);
      }
    });

    test('marks terminal request states as terminal', () {
      final states = ['delivered', 'completed', 'expired'];

      for (final state in states) {
        final request = DeliveryRequestModel(
          orderId: 'order-1',
          customerId: 'user-1',
          status: state,
          source: 'customer',
          requestedAt: DateTime.now(),
          deadlineAt: DateTime.now().add(const Duration(days: 2)),
        );

        expect(request.isActive, isFalse);
        expect(request.isTerminal, isTrue);
      }
    });

    test('allows duplicate guards based on active status', () {
      final active = DeliveryRequestModel(
        orderId: 'order-1',
        customerId: 'user-1',
        status: 'queued',
        source: 'customer',
        requestedAt: DateTime.now(),
        deadlineAt: DateTime.now().add(const Duration(days: 2)),
      );

      final terminal = DeliveryRequestModel(
        orderId: 'order-2',
        customerId: 'user-2',
        status: 'completed',
        source: 'customer',
        requestedAt: DateTime.now(),
        deadlineAt: DateTime.now().add(const Duration(days: 2)),
      );

      expect(active.isActive, isTrue);
      expect(terminal.isTerminal, isTrue);
    });
  });
}
