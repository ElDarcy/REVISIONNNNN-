import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/order_model.dart';
import '../engines/staff_assignment_engine.dart';
import '../services/notification_service.dart';
import 'order_load_engine.dart';
import 'order_status_flow_engine.dart';

/// Releases an order to the existing scheduler only after all preconditions
/// have been met. It deliberately does not schedule or assign any machine.
class OrderSchedulingGate {
  static bool isEligible(Map<String, dynamic> order) {
    final hasStaff =
        (order['assignedTo'] ?? order['staffId']) is String &&
        ((order['assignedTo'] ?? order['staffId']) as String).isNotEmpty;
    final actualWeight = (order['actualWeight'] as num?)?.toDouble();
    final weightVerified =
        order['weightStatus'] == 'verified' &&
        actualWeight != null &&
        actualWeight.isFinite &&
        actualWeight > 0;
    return order['paymentStatus'] == 'Verified' && hasStaff && weightVerified;
  }

  static Future<bool> releaseIfEligible(
    FirebaseFirestore firestore,
    String orderId,
  ) async {
    final ref = firestore.collection('orders').doc(orderId);
    await autoAssignLaundryStaffIfNeeded(firestore, orderId);
    final snapshot = await ref.get();
    if (!snapshot.exists || !isEligible(snapshot.data()!)) return false;

    final order = OrderModel.fromMap(snapshot.data()!, orderId);
    final loadIds = await OrderLoadEngine.createLoadsForOrder(firestore, order);
    await ref.update({
      'status': OrderStatusFlowEngine.statusPaymentVerified,
      'numberOfLoads': loadIds.length,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    return true;
  }

  /// Assign a laundry worker only after payment is verified.  This is
  /// idempotent so payment retries and concurrent clients cannot overwrite an
  /// existing assignment; an administrator may still reassign for exceptions.
  static Future<String?> autoAssignLaundryStaffIfNeeded(
    FirebaseFirestore firestore,
    String orderId,
  ) async {
    final orderRef = firestore.collection('orders').doc(orderId);
    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) return null;
    final orderData = orderSnap.data()!;
    if (orderData['paymentStatus'] != 'Verified' || _hasLaundryStaff(orderData))
      return null;

    final results = await Future.wait([
      firestore.collection('users').get(),
      firestore.collection('orders').get(),
    ]);
    final users = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final orders = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final staffIds = users.docs
        .where((doc) {
          final data = doc.data();
          return (data['role'] == 'staff' || data['role'] == 'laundry_staff') &&
              data['isActive'] != false;
        })
        .map((doc) => doc.id)
        .toList();
    if (staffIds.isEmpty) return null;

    final allOrders = orders.docs
        .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
        .toList();
    final selected = StaffAssignmentEngine.recommendStaffId(
      staffIds: staffIds,
      activeWorkloads: StaffAssignmentEngine.countActiveOrdersByStaff(
        allOrders,
      ),
      lastActive: StaffAssignmentEngine.lastActiveByStaff(allOrders),
    );
    if (selected == null) return null;

    final assigned = await firestore.runTransaction((transaction) async {
      final current = await transaction.get(orderRef);
      if (!current.exists) return false;
      final data = current.data()!;
      if (data['paymentStatus'] != 'Verified' || _hasLaundryStaff(data)) {
        return false;
      }
      transaction.update(orderRef, {
        'assignedTo': selected,
        'assignedStaffId': selected,
        'staffId': selected,
        'laundryStaffAssignmentSource': 'automatic',
        'laundryStaffAssignedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (assigned) {
      await NotificationService().sendNotification(
        userId: selected,
        title: 'Laundry task assigned',
        body:
            'You were automatically assigned order ${orderId.substring(0, 6).toUpperCase()}.',
        type: 'operational',
        orderId: orderId,
      );
      return selected;
    }
    return null;
  }

  static bool _hasLaundryStaff(Map<String, dynamic> order) {
    final staffId = order['assignedTo'] ?? order['staffId'];
    return staffId is String && staffId.isNotEmpty;
  }
}
