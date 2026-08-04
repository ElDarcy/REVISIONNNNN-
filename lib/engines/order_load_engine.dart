import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/order_load_model.dart';
import '../models/order_model.dart';
import '../models/laundry_status_model.dart';
import 'order_status_flow_engine.dart';

/// Engine that splits an order into multiple loads when its weight exceeds the
/// machine capacity (8kg per load).
///
///   numberOfLoads = ceil(totalWeight / 8)
///
/// Each load is stored as a separate document in the `orderLoads` collection
/// and follows its own status flow (`Waiting for Machine` → `Machine Assigned`
/// → `Washing` → `Drying` → `Completed`). The parent order status is derived
/// from the statuses of all its loads.
class OrderLoadEngine {
  /// Default machine capacity per load (kg).
  static const double capacityKg = 8.0;

  static const Uuid _uuid = Uuid();

  /// Number of loads needed for a given total weight:
  ///   numberOfLoads = ceil(totalWeight / capacityKg)
  static int computeNumberOfLoads(double totalWeight) {
    if (totalWeight <= 0) return 1;
    return (totalWeight / capacityKg).ceil();
  }

  /// Split [totalWeight] into per-load weights (each up to [capacityKg],
  /// the last load takes the remainder). Returns an empty list when the
  /// weight is not positive.
  static List<double> splitWeight(double totalWeight) {
    if (totalWeight <= 0) return [];
    final count = computeNumberOfLoads(totalWeight);
    final loads = <double>[];
    for (var i = 0; i < count; i++) {
      final remaining = totalWeight - i * capacityKg;
      loads.add(remaining >= capacityKg ? capacityKg : remaining);
    }
    return loads;
  }

  /// Build the per-load status flow for a given service type.
  ///
  /// - Wash Only:  Waiting for Machine → Machine Assigned → Washing → Completed
  /// - Dry Only:   Waiting for Dryer → Dryer Assigned → Drying → Completed
  /// - Wash & Dry: Waiting for Machine → Machine Assigned → Washing →
  ///               Waiting for Dryer → Dryer Assigned → Drying → Completed
  static List<String> getLoadFlow(String serviceType) {
    final service = OrderStatusFlowEngine.resolveServiceTypeFromData({
      'serviceType': serviceType,
    });
    final flow = <String>[];
    if (OrderStatusFlowEngine.needsWashing(service)) {
      flow.add(OrderStatusFlowEngine.statusWaitingForMachine);
      flow.add(OrderStatusFlowEngine.statusMachineAssigned);
      flow.add(OrderStatusFlowEngine.statusWashing);
    }
    if (OrderStatusFlowEngine.needsDrying(service)) {
      flow.add(OrderStatusFlowEngine.statusWaitingForDryer);
      flow.add(OrderStatusFlowEngine.statusDryerAssigned);
      flow.add(OrderStatusFlowEngine.statusDrying);
    }
    flow.add(OrderStatusFlowEngine.statusReadyForPickup);
    return flow;
  }

  /// The "ready" status a load reaches when its processing is complete,
  /// based on the delivery method of the parent order.
  static String readyStatusForLoad(OrderModel order) {
    return OrderStatusFlowEngine.readyStatus(order);
  }

  /// Create the `orderLoads` records for [order] in Firestore.
  /// Returns the created load ids (in load order). Idempotent: if loads
  /// already exist for the order, they are returned without re-creating.
  static Future<List<String>> createLoadsForOrder(
    FirebaseFirestore firestore,
    OrderModel order, {
    String? serviceTypeOverride,
  }) async {
    final existing = await firestore
        .collection('orderLoads')
        .where('orderId', isEqualTo: order.id)
        .get();
    if (existing.docs.isNotEmpty) {
      return existing.docs.map((doc) => doc.id).toList()..sort((a, b) {
        final an = (a).length;
        final bn = (b).length;
        return an.compareTo(bn);
      });
    }

    final serviceType = serviceTypeOverride ?? order.serviceType;
    final weights = splitWeight(order.weight);
    final batch = firestore.batch();
    final ids = <String>[];

    for (final weight in weights) {
      final loadId = _uuid.v4();
      ids.add(loadId);
      final load = OrderLoadModel(
        id: loadId,
        orderId: order.id,
        loadNumber: ids.length,
        weight: weight,
        serviceType: serviceType ?? 'Wash and Dry',
      );
      batch.set(firestore.collection('orderLoads').doc(loadId), load.toMap());
    }

    await batch.commit();
    return ids;
  }

  /// Derive the parent order status from its loads.
  ///
  /// Only when ALL loads are Completed does the order become
  /// `Ready for Pickup` / `Ready for Delivery`. Otherwise the order takes the
  /// most "advanced" processing status among its loads (falling back to
  /// [fallbackStatus] when there are no loads).
  static String deriveParentStatus(
    List<OrderLoadModel> loads,
    OrderModel order, {
    String fallbackStatus = '',
  }) {
    if (loads.isEmpty) {
      return fallbackStatus.isNotEmpty
          ? fallbackStatus
          : OrderStatusFlowEngine.statusPaymentVerified;
    }

    final service = OrderStatusFlowEngine.resolveServiceType(order);
    final flow = getLoadFlow(service);
    // Index of the most advanced status a load has reached so far.
    int maxIndex = -1;
    var allCompleted = true;

    for (final load in loads) {
      final idx = flow.indexOf(load.status.value);
      if (idx > maxIndex) maxIndex = idx;
      final isCompleted = load.status == LaundryStatus.completed;
      final isDelivered = load.status == LaundryStatus.delivered;
      if (!isCompleted && !isDelivered) {
        allCompleted = false;
      }
    }

    // All loads finished -> order is ready for pickup/delivery.
    if (allCompleted) {
      return OrderStatusFlowEngine.readyStatus(order);
    }

    // Otherwise reflect the most advanced processing status.
    if (maxIndex >= 0 && maxIndex < flow.length) {
      final status = flow[maxIndex];
      // If the most advanced is a "ready" status but not all loads are done,
      // keep the order in a processing state.
      if (status == OrderStatusFlowEngine.statusReadyForPickup ||
          status == OrderStatusFlowEngine.statusReadyForDelivery) {
        return flow.isNotEmpty ? flow[flow.length - 2] : status;
      }
      return status;
    }

    return fallbackStatus.isNotEmpty
        ? fallbackStatus
        : OrderStatusFlowEngine.statusPaymentVerified;
  }
}
