import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_app/engines/order_status_flow_engine.dart';
import 'package:laundry_app/models/laundry_status_model.dart';
import 'package:laundry_app/models/order_model.dart';

OrderModel _order({String? deliveryRequestStatus}) => OrderModel(
      id: 'order-1',
      userId: 'customer-1',
      deliveryMethod: 'Drop-off',
      deliveryRequestStatus: deliveryRequestStatus,
      status: LaundryStatus.readyForPickup,
    );

void main() {
  test('no delivery progress exists before a customer delivery request', () {
    final flow = OrderStatusFlowEngine.getFullFlow(_order());

    expect(OrderStatusFlowEngine.readyStatus(_order()), 'Ready for Pickup');
    expect(flow, isNot(contains('Out for Delivery')));
    expect(flow, isNot(contains('Awaiting Pickup')));
  });

  test('delivery progress is added only after the request is persisted', () {
    final order = _order(deliveryRequestStatus: 'queued');
    final flow = OrderStatusFlowEngine.getFullFlow(order);

    expect(OrderStatusFlowEngine.readyStatus(order), 'Ready for Delivery');
    expect(flow, contains('Out for Delivery'));
  });
}
