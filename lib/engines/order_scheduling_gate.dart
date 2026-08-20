import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../config/app_config.dart';
import '../models/order_model.dart';
import '../models/laundry_status_model.dart';
import '../engines/staff_assignment_engine.dart';
import '../services/notification_service.dart';
import 'order_load_engine.dart';
import 'order_status_flow_engine.dart';
import 'service_time_estimator.dart';

/// Which staff an order currently needs before it can be processed.
enum AssignmentPhase {
  /// 'Pickup' order whose laundry has not been collected yet — needs a
  /// delivery staff member for the pickup leg.
  pickup,

  /// Pickup order with cash that was collected but not yet remitted and
  /// confirmed by admin — processing must wait (strict cash handover gate).
  waitForCashRemittance,

  /// Laundry is at the shop (or the order is Drop-off) — needs a laundry worker.
  laundry,
}

/// Releases an order to the existing scheduler only after all preconditions
/// have been met. It deliberately does not schedule or assign any machine.
class OrderSchedulingGate {
  /// Pure phase decision. Exposed for tests.
  static AssignmentPhase resolveAssignmentPhase(Map<String, dynamic> order) {
    final deliveryMethod = (order['deliveryMethod'] as String?) ?? 'Drop-off';
    if (deliveryMethod != 'Pickup') return AssignmentPhase.laundry;

    final collected =
        order['pickupStatus'] == LaundryStatus.collected.value;
    if (!collected) return AssignmentPhase.pickup;

    // Laundry is at the shop. For cash pickup orders the laundry worker is
    // only assigned once the collected cash has been remitted and confirmed.
    final paymentMethod = order['paymentMethod'] as String?;
    if (AppConfig.isCashMethod(paymentMethod)) {
      final remitted = order['remittanceStatus'] == AppConfig.remittanceConfirmed;
      if (!remitted) return AssignmentPhase.waitForCashRemittance;
    }
    return AssignmentPhase.laundry;
  }

  static bool isEligible(Map<String, dynamic> order) {
    return checkEligibility(order).values.every((ok) => ok);
  }

  /// Evaluates every eligibility condition independently and reports which ones
  /// currently pass. Callers (e.g. the machine-scheduler sweep) use this to log
  /// exactly why an order is blocked instead of silently skipping it.
  static Map<String, bool> checkEligibility(Map<String, dynamic> order) {
    final hasStaff =
        (order['assignedTo'] ?? order['staffId']) is String &&
        ((order['assignedTo'] ?? order['staffId']) as String).isNotEmpty;
    final actualWeight = (order['actualWeight'] as num?)?.toDouble();
    final weightVerified =
        order['weightStatus'] == 'verified' &&
        actualWeight != null &&
        actualWeight.isFinite &&
        actualWeight > 0;
    // Cash orders only release once the cash has been physically collected
    // (paymentStatus 'Verified'). 'Pending Collection' alone — e.g. a drop-off
    // cash order that has not been collected at the counter yet — must never
    // release processing. GCash orders release once the admin verifies.
    final isCash = AppConfig.isCashMethod(order['paymentMethod'] as String?);
    final paymentOk =
        order['paymentStatus'] == 'Verified' ||
        (!isCash && order['paymentStatus'] == 'Pending Collection');
    // Pickup orders must have their laundry physically at the shop before
    // processing, and cash pickup orders only after the cash is remitted and
    // confirmed by admin (strict cash handover gate). Drop-off orders are
    // unaffected — cash collected at the counter proceeds as before.
    final isPickup = order['deliveryMethod'] == 'Pickup';
    final pickupComplete =
        !isPickup || order['pickupStatus'] == LaundryStatus.collected.value;
    final cashRemitted = !isPickup ||
        !isCash ||
        order['remittanceStatus'] == AppConfig.remittanceConfirmed;
    return {
      'hasStaff': hasStaff,
      'weightVerified': weightVerified,
      'paymentOk': paymentOk,
      'pickupComplete': pickupComplete,
      'cashRemitted': cashRemitted,
    };
  }

  /// Human-readable summary of which eligibility conditions are NOT met.
  /// Returns 'eligible' when every condition passes.
  static String describeBlockers(Map<String, dynamic> order) {
    final results = checkEligibility(order);
    final failing = results.entries
        .where((e) => !e.value)
        .map((e) => e.key)
        .toList();
    if (failing.isEmpty) return 'eligible';
    return 'blocked by: ${failing.join(', ')}';
  }

  static Future<bool> releaseIfEligible(
    FirebaseFirestore firestore,
    String orderId,
  ) async {
    final ref = firestore.collection('orders').doc(orderId);
    // Assign the staff for the current phase (pickup leg vs. laundry leg).
    // For a pickup order still waiting on cash remittance this returns null and
    // the order stays blocked, matching the strict cash handover gate.
    // Assignment is best-effort: a failed recommendation (e.g. the calling
    // client lacks permission to read the staff roster) must never block an
    // otherwise valid release or an order creation.
    try {
      await autoAssignForPhase(firestore, orderId);
    } catch (e) {
      debugPrint('autoAssignForPhase error: $e');
    }
    final snapshot = await ref.get();
    if (!snapshot.exists) {
      debugPrint('releaseIfEligible: order $orderId does not exist.');
      return false;
    }
    if (!isEligible(snapshot.data()!)) {
      debugPrint(
        'releaseIfEligible: order $orderId not released — '
        '${describeBlockers(snapshot.data()!)}',
      );
      return false;
    }

    final order = OrderModel.fromMap(snapshot.data()!, orderId);
    final loadIds = await OrderLoadEngine.createLoadsForOrder(firestore, order);

    // Wrap status update in a transaction for race-condition safety.
    await firestore.runTransaction((txn) async {
      final doc = await txn.get(ref);
      if (!doc.exists || !isEligible(doc.data()!)) return;
      final now = DateTime.now();
      final update = <String, dynamic>{
        'status': OrderStatusFlowEngine.statusPaymentVerified,
        'numberOfLoads': loadIds.length,
        'updatedAt': now.toIso8601String(),
      };
      // The order-level laundry timer is anchored to the moment the order
      // becomes eligible for processing (payment + weight + staff satisfied) —
      // never at creation, payment submission, or machine reservation. Per-load
      // timers still start only when staff clicks Start Wash/Start Dry.
      final data = doc.data()!;
      if (data['processingStartedAt'] == null) {
        final cycles = loadIds.isNotEmpty
            ? loadIds.length
            : ServiceTimeEstimator.getCycleCount(
                (data['actualWeight'] ?? data['weight'] as num?)?.toDouble() ?? 0,
              );
        final minutes = ServiceTimeEstimator.estimateMinutesForCycles(cycles);
        update['processingStartedAt'] = now.toIso8601String();
        update['estimatedFinishTime'] = now
            .add(Duration(minutes: minutes))
            .toIso8601String();
      }
      txn.update(ref, update);
    });
    return true;
  }

  /// Document id used for a pickup-leg entry in `deliveryQueue`. Using a
  /// distinct id (`{orderId}__pickup`) avoids colliding with the final
  /// delivery entry (`{orderId}`) that `chooseFulfillment` may create later.
  static String pickupQueueDocId(String orderId) => '${orderId}__pickup';

  /// Self-healing pass that makes sure every pickup order has a `deliveryQueue`
  /// pickup entry with a delivery staff assigned to it.
  ///
  /// This is the client-side replacement for the (paid) `autoAssignPickupTask`
  /// cloud trigger: it runs from a staff/admin client — which demonstrably has
  /// write access to `deliveryQueue` — so pickup tasks are created and assigned
  /// even when the customer placed the order from an app whose security rules
  /// deny `deliveryQueue` writes. Cheap single-field query (no composite index
  /// required); call it when a staff screen loads and on a short timer.
  static Future<void> reconcilePendingPickups(
    FirebaseFirestore firestore,
  ) async {
    try {
      final pending = await firestore
          .collection('orders')
          .where('pickupStatus', isEqualTo: 'Pending Pickup')
          .get();
      for (final doc in pending.docs) {
        final data = doc.data();
        if (data['deliveryMethod'] != 'Pickup') continue;
        try {
          await autoAssignForPhase(firestore, doc.id);
        } catch (e) {
          debugPrint('reconcilePendingPickups assign error for ${doc.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('reconcilePendingPickups error: $e');
    }
  }

  /// Assign the staff needed by the order's current phase and return the
  /// assigned staff id (or null when none is available / must wait).
  ///
  /// - Pickup leg  → assigns a delivery staff member and creates the pickup
  ///   `deliveryQueue` entry (type 'pickup').
  /// - Cash remittance wait → returns null (order stays blocked).
  /// - Laundry leg → assigns a laundry worker (existing behavior).
  static Future<String?> autoAssignForPhase(
    FirebaseFirestore firestore,
    String orderId,
  ) async {
    final orderSnap = await firestore.collection('orders').doc(orderId).get();
    if (!orderSnap.exists) return null;
    final orderData = orderSnap.data()!;
    switch (resolveAssignmentPhase(orderData)) {
      case AssignmentPhase.pickup:
        return _assignPickupDeliveryStaff(firestore, orderId, orderData);
      case AssignmentPhase.waitForCashRemittance:
        return null;
      case AssignmentPhase.laundry:
        return autoAssignLaundryStaffIfNeeded(firestore, orderId);
    }
  }

  static Future<String?> _assignPickupDeliveryStaff(
    FirebaseFirestore firestore,
    String orderId,
    Map<String, dynamic> orderData,
  ) async {
    try {
      final queueRef =
          firestore.collection('deliveryQueue').doc(pickupQueueDocId(orderId));
      final orderRef = firestore.collection('orders').doc(orderId);
      // Recommend the least-loaded delivery staff BEFORE the transaction, since
      // collection queries cannot run inside a transaction.
      final staffId = await _recommendDeliveryStaff(firestore);

      // Single transaction owns the create-or-fill decision so concurrent
      // reconciles (Admin Web + Delivery Staff app) are idempotent: the
      // deterministic doc id `{orderId}__pickup` makes duplicate entries
      // impossible, and only the winning client writes the assignment, so no
      // duplicate staff assignments or duplicate notifications can occur.
      final result = await firestore.runTransaction((txn) async {
        final queueSnap = await txn.get(queueRef);
        if (queueSnap.exists) {
          final data = queueSnap.data()!;
          final assigned = data['assignedTo'];
          if (assigned is String && assigned.isNotEmpty) {
            // Already assigned (possibly by a concurrent pass). Keep the order
            // fields in sync — idempotent, and no notification is sent.
            final orderSnap = await txn.get(orderRef);
            final currentOrder = orderSnap.data();
            if (currentOrder?['assignedDeliveryStaffId'] != assigned) {
              txn.update(orderRef, {
                'assignedDeliveryStaffId': assigned,
                'pickupStatus': data['status'] ?? 'Pending Pickup',
                'updatedAt': FieldValue.serverTimestamp(),
              });
            }
            return _PickupAssignResult(assigned, assignedByThisClient: false);
          }
          // Entry exists but nobody is assigned yet (e.g. it was created by a
          // client that could not read the staff roster). Fill it here.
          if (staffId != null) {
            txn.update(queueRef, {'assignedTo': staffId});
            txn.update(orderRef, {
              'assignedDeliveryStaffId': staffId,
              'pickupStatus': 'Pending Pickup',
              'updatedAt': FieldValue.serverTimestamp(),
            });
            return _PickupAssignResult(staffId, assignedByThisClient: true);
          }
          return const _PickupAssignResult(null, assignedByThisClient: false);
        }

        // No entry yet — create it (unassigned when no staff is recommended).
        final lat = (orderData['customerLatitude'] ?? 0).toDouble();
        final lng = (orderData['customerLongitude'] ?? 0).toDouble();
        // Even when no staff could be recommended (empty roster or the calling
        // client lacks permission to read `users`), still create the pickup
        // entry unassigned — the periodic reconcile pass (or a later
        // releaseIfEligible call) fills the assignment.
        txn.set(
          queueRef,
          {
            'orderId': orderId,
            'transactionNumber': orderData['transactionNumber'],
            'customerId': orderData['userId'],
            'customerName': orderData['customerName'],
            'type': 'pickup',
            'address': _extractAddress(orderData['deliveryAddress']),
            'latitude': lat,
            'longitude': lng,
            'distanceKm': orderData['distanceKm'] ?? 0,
            'priorityScore': 50,
            'status': 'Pending Pickup',
            'assignedTo': staffId,
            'createdAt': DateTime.now().toIso8601String(),
          },
        );
        if (staffId != null) {
          txn.update(orderRef, {
            'assignedDeliveryStaffId': staffId,
            'pickupStatus': 'Pending Pickup',
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return _PickupAssignResult(staffId, assignedByThisClient: true);
        }
        return const _PickupAssignResult(null, assignedByThisClient: false);
      });

      if (result.assignedByThisClient && result.staffId != null) {
        await NotificationService().sendNotification(
          userId: result.staffId!,
          title: 'Pickup task assigned',
          body:
              'You were automatically assigned to pick up transaction ${orderId.substring(0, 6).toUpperCase()}.',
          type: 'operational',
          orderId: orderId,
        );
      }
      return result.staffId;
    } catch (e) {
      debugPrint('_assignPickupDeliveryStaff error: $e');
      return null;
    }
  }

  static String? _extractAddress(dynamic address) {
    if (address == null) return null;
    if (address is String) return address;
    if (address is Map) {
      return (address['fullAddress'] as String?) ??
          (address['street'] as String?);
    }
    return null;
  }

  /// Recommend the least-loaded active delivery staff member.
  static Future<String?> _recommendDeliveryStaff(
    FirebaseFirestore firestore,
  ) async {
    final usersSnap = await firestore
        .collection('users')
        .where('role', isEqualTo: 'delivery_staff')
        .where('isActive', isEqualTo: true)
        .get();
    if (usersSnap.docs.isEmpty) return null;
    final deliveryStaffIds = usersSnap.docs.map((d) => d.id).toList();

    final queueSnap = await firestore
        .collection('deliveryQueue')
        .where('status', whereIn: [
          'Pending Pickup',
          'Pickup Assigned',
          'Pending Delivery',
          'Out for Delivery',
        ])
        .get();
    final counts = <String, int>{};
    for (final doc in queueSnap.docs) {
      final staffId = doc['assignedTo'] as String?;
      if (staffId != null && staffId.isNotEmpty) {
        counts[staffId] = (counts[staffId] ?? 0) + 1;
      }
    }
    deliveryStaffIds.sort((a, b) {
      final countA = counts[a] ?? 0;
      final countB = counts[b] ?? 0;
      if (countA != countB) return countA.compareTo(countB);
      return a.compareTo(b);
    });
    return deliveryStaffIds.first;
  }

  /// Assign a laundry worker after the transaction is approved.
  /// This is idempotent — concurrent clients cannot overwrite an existing
  /// assignment; an administrator may still reassign for exceptions.
  ///
  /// BUG FIX: Removed the paymentStatus == 'Verified' guard. Staff should
  /// be assigned immediately after approval so they are ready when payment
  /// clears. The scheduling gate still prevents load creation until payment
  /// is verified.
  static Future<String?> autoAssignLaundryStaffIfNeeded(
    FirebaseFirestore firestore,
    String orderId,
  ) async {
    final orderRef = firestore.collection('orders').doc(orderId);
    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) return null;
    final orderData = orderSnap.data()!;
    // Skip if staff already assigned (idempotent guard).
    if (_hasLaundryStaff(orderData)) return null;

    final results = await Future.wait([
      firestore.collection('users').get(),
      firestore.collection('orders').get(),
    ]);
    final users = results[0];
    final orders = results[1];
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

    // BUG FIX: Double-check inside transaction that no staff was assigned in the meantime
    final assigned = await firestore.runTransaction((transaction) async {
      final current = await transaction.get(orderRef);
      if (!current.exists) return false;
      final data = current.data()!;
      if (_hasLaundryStaff(data)) return false;
      transaction.update(orderRef, {
        'assignedTo': selected,
        'assignedStaffId': selected,
        'staffId': selected,
        'laundryStaffAssignmentSource': 'automatic_sdk',
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
            'You were automatically assigned transaction ${orderId.substring(0, 6).toUpperCase()}.',
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

/// Outcome of a transaction-scoped pickup assignment. Tells the caller whether
/// THIS client performed the assignment (and should therefore notify the staff)
/// versus merely observing an existing assignment from a concurrent pass.
class _PickupAssignResult {
  const _PickupAssignResult(this.staffId, {required this.assignedByThisClient});

  final String? staffId;
  final bool assignedByThisClient;
}
