import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_app/engines/order_load_engine.dart';
import 'package:laundry_app/models/order_model.dart';

void main() {
  group('OrderLoadEngine.splitWeight', () {
    final cases = <double, List<double>>{
      8: [8],
      10: [5, 5],
      12: [6, 6],
      15: [7.5, 7.5],
      16: [8, 8],
      17: [5.67, 5.67, 5.66],
      20: [6.67, 6.67, 6.66],
      8.2: [4.1, 4.1],
      8.5: [4.25, 4.25],
      8.235: [4.118, 4.117],
      12.3: [6.15, 6.15],
      16.5: [5.5, 5.5, 5.5],
    };

    for (final entry in cases.entries) {
      test('${entry.key} kg is split evenly without exceeding capacity', () {
        final loads = OrderLoadEngine.splitWeight(entry.key);

        expect(loads, entry.value);
        expect(loads.length, OrderLoadEngine.computeNumberOfLoads(entry.key));
        expect(loads.every((weight) => weight <= OrderLoadEngine.capacityKg), isTrue);
        expect(
          loads.fold<double>(0, (sum, weight) => sum + weight),
          closeTo(entry.key, 0.000000001),
        );
      });
    }
  });

  group('OrderLoadEngine actual-weight logic', () {
    test('uses verified actual weight for final load count and preserves estimated weight', () {
      const estimatedWeight = 10.0;
      const actualWeight = 9.82;

      final effectiveWeight = OrderLoadEngine.effectiveWeightForOrder(
        OrderModel(
          id: 'order-1',
          userId: 'user-1',
          weight: estimatedWeight,
          estimatedWeight: estimatedWeight,
          actualWeight: actualWeight,
          weightStatus: 'verified',
        ),
      );

      expect(effectiveWeight, closeTo(actualWeight, 0.000000001));
      expect(OrderLoadEngine.computeNumberOfLoads(effectiveWeight), 2);
    });
  });
}
