import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_app/config/app_config.dart';
import 'package:laundry_app/engines/financial_settlement_engine.dart';
import 'package:laundry_app/engines/order_scheduling_gate.dart';
import 'package:laundry_app/engines/order_status_flow_engine.dart';
import 'package:laundry_app/models/order_model.dart';

void main() {
  group('OrderSchedulingGate.isEligible', () {
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

    test('pending weight is not eligible (staff submission is the only gate)',
        () {
      expect(
        OrderSchedulingGate.isEligible({
          'paymentStatus': 'Verified',
          'assignedTo': 'staff-1',
          'weightStatus': 'pending',
          'weight': 10.0,
        }),
        isFalse,
      );
    });

    test('rejects legacy or missing actual weight instead of using declared weight',
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
    });

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

    test('requires a staff assignment before scheduling', () {
      expect(
        OrderSchedulingGate.isEligible({
          'paymentStatus': 'Verified',
          'assignedTo': null,
          'weightStatus': 'verified',
          'actualWeight': 8.0,
        }),
        isFalse,
      );
    });
  });

  group('OrderSchedulingGate.resolveAssignmentPhase', () {
    test('drop-off orders always need a laundry worker', () {
      expect(
        OrderSchedulingGate.resolveAssignmentPhase({
          'deliveryMethod': 'Drop-off',
        }),
        AssignmentPhase.laundry,
      );
    });

    test('pickup order before collection needs a delivery staff', () {
      expect(
        OrderSchedulingGate.resolveAssignmentPhase({
          'deliveryMethod': 'Pickup',
          'pickupStatus': 'Pending Pickup',
        }),
        AssignmentPhase.pickup,
      );
      expect(
        OrderSchedulingGate.resolveAssignmentPhase({
          'deliveryMethod': 'Pickup',
          'pickupStatus': 'Pickup Assigned',
        }),
        AssignmentPhase.pickup,
      );
    });

    test('pickup order with GCash moves to the laundry leg once collected', () {
      expect(
        OrderSchedulingGate.resolveAssignmentPhase({
          'deliveryMethod': 'Pickup',
          'pickupStatus': 'Laundry Collected',
          'paymentMethod': 'GCash',
        }),
        AssignmentPhase.laundry,
      );
    });

    test('cash pickup waits for remittance confirmation before the laundry leg',
        () {
      expect(
        OrderSchedulingGate.resolveAssignmentPhase({
          'deliveryMethod': 'Pickup',
          'pickupStatus': 'Laundry Collected',
          'paymentMethod': 'Cash on Pickup',
          'remittanceStatus': null,
        }),
        AssignmentPhase.waitForCashRemittance,
      );
      expect(
        OrderSchedulingGate.resolveAssignmentPhase({
          'deliveryMethod': 'Pickup',
          'pickupStatus': 'Laundry Collected',
          'paymentMethod': 'Cash on Pickup',
          'remittanceStatus': 'Pending Remittance',
        }),
        AssignmentPhase.waitForCashRemittance,
      );
      expect(
        OrderSchedulingGate.resolveAssignmentPhase({
          'deliveryMethod': 'Pickup',
          'pickupStatus': 'Laundry Collected',
          'paymentMethod': 'Cash on Pickup',
          'remittanceStatus': 'Remitted',
        }),
        AssignmentPhase.laundry,
      );
    });
  });

  group('OrderSchedulingGate pickup-phase eligibility', () {
    test('pickup order is not schedulable until its laundry is collected', () {
      expect(
        OrderSchedulingGate.isEligible({
          'deliveryMethod': 'Pickup',
          'pickupStatus': 'Pickup Assigned',
          'paymentStatus': 'Verified',
          'assignedTo': 'staff-1',
          'weightStatus': 'verified',
          'actualWeight': 9.0,
        }),
        isFalse,
      );
      expect(
        OrderSchedulingGate.isEligible({
          'deliveryMethod': 'Pickup',
          'pickupStatus': 'Laundry Collected',
          'paymentStatus': 'Verified',
          'assignedTo': 'staff-1',
          'weightStatus': 'verified',
          'actualWeight': 9.0,
        }),
        isTrue,
      );
    });

    test('cash pickup is not schedulable until cash is remitted and confirmed',
        () {
      expect(
        OrderSchedulingGate.isEligible({
          'deliveryMethod': 'Pickup',
          'pickupStatus': 'Laundry Collected',
          'paymentMethod': 'Cash on Pickup',
          'remittanceStatus': 'Pending Remittance',
          'paymentStatus': 'Verified',
          'assignedTo': 'staff-1',
          'weightStatus': 'verified',
          'actualWeight': 9.0,
        }),
        isFalse,
      );
      expect(
        OrderSchedulingGate.isEligible({
          'deliveryMethod': 'Pickup',
          'pickupStatus': 'Laundry Collected',
          'paymentMethod': 'Cash on Pickup',
          'remittanceStatus': 'Remitted',
          'paymentStatus': 'Verified',
          'assignedTo': 'staff-1',
          'weightStatus': 'verified',
          'actualWeight': 9.0,
        }),
        isTrue,
      );
    });

    test('drop-off cash at shop does not wait on remittance', () {
      expect(
        OrderSchedulingGate.isEligible({
          'deliveryMethod': 'Drop-off',
          'paymentMethod': 'Cash at Shop',
          'remittanceStatus': null,
          'paymentStatus': 'Verified',
          'assignedTo': 'staff-1',
          'weightStatus': 'verified',
          'actualWeight': 9.0,
        }),
        isTrue,
      );
    });

    test('cash orders are not schedulable on Pending Collection alone', () {
      // Drop-off cash waiting to be collected at the counter must NOT release.
      expect(
        OrderSchedulingGate.isEligible({
          'deliveryMethod': 'Drop-off',
          'paymentMethod': 'Cash on Drop off',
          'paymentStatus': 'Pending Collection',
          'assignedTo': 'staff-1',
          'weightStatus': 'verified',
          'actualWeight': 9.0,
        }),
        isFalse,
      );
      // Once the counter staff collects it, the order is eligible (Verified).
      expect(
        OrderSchedulingGate.isEligible({
          'deliveryMethod': 'Drop-off',
          'paymentMethod': 'Cash on Drop off',
          'paymentStatus': 'Verified',
          'assignedTo': 'staff-1',
          'weightStatus': 'verified',
          'actualWeight': 9.0,
        }),
        isTrue,
      );
      // Pickup cash before collection is equally blocked.
      expect(
        OrderSchedulingGate.isEligible({
          'deliveryMethod': 'Pickup',
          'pickupStatus': 'Pending Pickup',
          'paymentMethod': 'Cash on Pickup',
          'paymentStatus': 'Pending Collection',
          'assignedTo': 'staff-1',
          'weightStatus': 'verified',
          'actualWeight': 9.0,
        }),
        isFalse,
      );
    });

    test('AppConfig treats Cash on Drop off as a cash method', () {
      expect(AppConfig.isCashMethod('Cash on Drop off'), isTrue);
      expect(AppConfig.isCashMethod('Cash on Pickup'), isTrue);
      expect(AppConfig.isCashMethod('Cash at Shop'), isTrue);
      expect(AppConfig.isCashMethod('GCash'), isFalse);
    });
  });

  group('FinancialSettlementEngine', () {
    test('exact payment leaves no balance or refund', () {
      final finalAmount = 250.0;
      final amountPaid = 250.0;
      expect(
        FinancialSettlementEngine.balanceDue(
          finalAmount: finalAmount,
          amountPaid: amountPaid,
        ),
        0,
      );
      expect(
        FinancialSettlementEngine.refundAmount(
          finalAmount: finalAmount,
          amountPaid: amountPaid,
        ),
        0,
      );
    });

    test('underpayment creates an outstanding balance and no refund', () {
      final finalAmount = 250.0;
      final amountPaid = 100.0;
      expect(
        FinancialSettlementEngine.balanceDue(
          finalAmount: finalAmount,
          amountPaid: amountPaid,
        ),
        150.0,
      );
      expect(
        FinancialSettlementEngine.refundAmount(
          finalAmount: finalAmount,
          amountPaid: amountPaid,
        ),
        0,
      );
    });

    test('overpayment creates a refund and no balance', () {
      final finalAmount = 250.0;
      final amountPaid = 300.0;
      expect(
        FinancialSettlementEngine.balanceDue(
          finalAmount: finalAmount,
          amountPaid: amountPaid,
        ),
        0,
      );
      expect(
        FinancialSettlementEngine.refundAmount(
          finalAmount: finalAmount,
          amountPaid: amountPaid,
        ),
        50.0,
      );
    });

    test('never reports a balance or refund when the final amount is unknown', () {
      expect(
        FinancialSettlementEngine.balanceDue(finalAmount: 0, amountPaid: 100),
        0,
      );
      expect(
        FinancialSettlementEngine.refundAmount(finalAmount: 0, amountPaid: 100),
        0,
      );
    });

    test('settlement requires the balance to be collected when one is owed', () {
      expect(
        FinancialSettlementEngine.isSettled(
          finalAmount: 250,
          amountPaid: 100,
          balanceSettled: true,
          refundSettled: false,
        ),
        isTrue,
      );
      expect(
        FinancialSettlementEngine.isSettled(
          finalAmount: 250,
          amountPaid: 100,
          balanceSettled: false,
          refundSettled: false,
        ),
        isFalse,
      );
    });

    test('settlement requires the refund to be returned when one is due', () {
      expect(
        FinancialSettlementEngine.isSettled(
          finalAmount: 250,
          amountPaid: 300,
          balanceSettled: false,
          refundSettled: true,
        ),
        isTrue,
      );
      expect(
        FinancialSettlementEngine.isSettled(
          finalAmount: 250,
          amountPaid: 300,
          balanceSettled: false,
          refundSettled: false,
        ),
        isFalse,
      );
    });
  });

  group('OrderModel financial getters', () {
    test('outstandingBalance follows the same clamp math as the engine', () {
      final order = OrderModel.fromMap({
        'finalAmount': 250.0,
        'amountPaid': 100.0,
        'balanceDue': 150.0,
      }, 'order-1');
      expect(order.outstandingBalance, 150.0);
      expect(order.pendingRefund, 0);
      expect(order.isFinanciallySettled, isFalse);
    });

    test('refund is outstanding until refundSettled is recorded', () {
      final order = OrderModel.fromMap({
        'finalAmount': 250.0,
        'amountPaid': 300.0,
        'refundAmount': 50.0,
        'refundSettled': false,
      }, 'order-2');
      expect(order.outstandingBalance, 0);
      expect(order.pendingRefund, 50.0);
      expect(order.isFinanciallySettled, isFalse);

      final settled = OrderModel.fromMap({
        'finalAmount': 250.0,
        'amountPaid': 300.0,
        'refundAmount': 50.0,
        'refundSettled': true,
      }, 'order-3');
      expect(settled.isFinanciallySettled, isTrue);
    });
  });

  group('OrderStatusFlowEngine cancel helpers', () {
    test('customer can cancel only before processing starts', () {
      final preProcessing = OrderModel.fromMap({
        'status': 'pending',
        'processingStartedAt': null,
      }, 'order-cancel-1');
      expect(
        OrderStatusFlowEngine.canCustomerCancel(preProcessing),
        isTrue,
      );

      final inProcessing = OrderModel.fromMap({
        'status': 'order_received',
        'processingStartedAt': DateTime.now().toIso8601String(),
      }, 'order-cancel-2');
      expect(
        OrderStatusFlowEngine.canCustomerCancel(inProcessing),
        isFalse,
      );
    });

    test('customer cannot cancel a finished or cancelled order', () {
      final done = OrderModel.fromMap({
        'status': 'completed',
        'processingStartedAt': DateTime.now().toIso8601String(),
      }, 'order-cancel-3');
      expect(OrderStatusFlowEngine.canCustomerCancel(done), isFalse);

      final cancelled = OrderModel.fromMap({
        'status': 'Cancelled',
        'processingStartedAt': null,
      }, 'order-cancel-4');
      expect(OrderStatusFlowEngine.canCustomerCancel(cancelled), isFalse);
    });

    test('cancelRefundAmount equals amountPaid for prepaid orders', () {
      final prepaid = OrderModel.fromMap({
        'amountPaid': 350.0,
      }, 'order-cancel-5');
      expect(OrderStatusFlowEngine.cancelRefundAmount(prepaid), 350.0);

      final unpaid = OrderModel.fromMap({
        'amountPaid': 0.0,
      }, 'order-cancel-6');
      expect(OrderStatusFlowEngine.cancelRefundAmount(unpaid), 0.0);
    });
  });
}