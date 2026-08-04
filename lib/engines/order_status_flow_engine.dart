import '../models/order_model.dart';
import '../models/machine_model.dart';
import '../core/constants/app_constants.dart';

/// Central engine that determines service-specific order status flows.
///
/// Supports three services:
/// - Wash Only    → Order Received → Payment Pending Verification → Payment Verified
///                  → (Waiting for Machine) → Washing → Ready for Pickup/Delivery
///                  → (Out for Delivery) → Completed
/// - Dry Only     → Order Received → Payment Pending Verification → Payment Verified
///                  → (Waiting for Dryer) → Drying → Ready for Pickup/Delivery
///                  → (Out for Delivery) → Completed
/// - Wash + Dry   → Order Received → Payment Pending Verification → Payment Verified
///                  → (Waiting for Machine) → Washing → (Waiting for Dryer) → Drying
///                  → Ready for Pickup/Delivery → (Out for Delivery) → Completed
///
/// "Waiting for Machine"/"Waiting for Dryer" are only inserted when no
/// washer/dryer is currently available. If a machine is available the order
/// goes straight into Washing/Drying.
class OrderStatusFlowEngine {
  static const String serviceWashOnly = 'Wash Only';
  static const String serviceDryOnly = 'Dry Only';
  static const String serviceWashDry = 'Wash and Dry';

  static const String statusOrderReceived = 'Order Received';
  static const String statusPaymentPendingVerification =
      'Payment Pending Verification';
  static const String statusPaymentVerified = 'Payment Verified';
  static const String statusWaitingForMachine = 'Waiting for Machine';
  static const String statusMachineAssigned = 'Machine Assigned';
  static const String statusDryerAssigned = 'Dryer Assigned';
  static const String statusWashing = 'Washing';
  static const String statusWaitingForDryer = 'Waiting for Dryer';
  static const String statusDrying = 'Drying';
  static const String statusReadyForDelivery = 'Ready for Delivery';
  static const String statusReadyForPickup = 'Ready for Pickup';
  static const String statusOutForDelivery = 'Out for Delivery';
  static const String statusCompleted = 'Completed';

  static String _normalize(String name) {
    final lower = name.toLowerCase().trim();
    if (lower.contains('wash') && lower.contains('dry')) return serviceWashDry;
    if (lower.contains('wash')) return serviceWashOnly;
    if (lower.contains('dry')) return serviceDryOnly;
    return serviceWashDry;
  }

  /// Resolve the service type for an order.
  static String resolveServiceType(OrderModel order) {
    if (order.serviceType != null && order.serviceType!.isNotEmpty) {
      return _normalize(order.serviceType!);
    }
    if (order.items.isNotEmpty) {
      final name = order.items.first.serviceName;
      if (name.isNotEmpty) return _normalize(name);
    }
    return serviceWashDry;
  }

  /// Resolve the service type from a raw Firestore order data map.
  static String resolveServiceTypeFromData(Map<String, dynamic> orderData) {
    final serviceType = orderData['serviceType'] as String?;
    if (serviceType != null && serviceType.isNotEmpty) {
      return _normalize(serviceType);
    }
    final items = orderData['items'] as List<dynamic>?;
    if (items != null && items.isNotEmpty) {
      final name = (items.first['serviceName'] as String?) ?? '';
      if (name.isNotEmpty) return _normalize(name);
    }
    return serviceWashDry;
  }

  /// Whether the service goes through washing.
  static bool needsWashing(String serviceType) {
    return _normalize(serviceType) != serviceDryOnly;
  }

  /// Whether the service goes through drying.
  static bool needsDrying(String serviceType) {
    return _normalize(serviceType) != serviceWashOnly;
  }

  /// Delivery is involved when the customer chose 'Pickup'.
  static bool hasDelivery(OrderModel order) {
    return order.deliveryMethod == 'Pickup';
  }

  /// The ready status depends on the delivery method.
  static String readyStatus(OrderModel order) {
    return hasDelivery(order) ? statusReadyForDelivery : statusReadyForPickup;
  }

  /// Base (happy-path) flow without the conditional waiting statuses.
  static List<String> getBaseFlow(OrderModel order) {
    final service = resolveServiceType(order);
    final flow = <String>[
      statusOrderReceived,
      statusPaymentPendingVerification,
      statusPaymentVerified,
    ];
    if (needsWashing(service)) {
      flow.add(statusMachineAssigned);
      flow.add(statusWashing);
    }
    if (needsDrying(service)) {
      flow.add(statusDryerAssigned);
      flow.add(statusDrying);
    }
    flow.add(readyStatus(order));
    if (hasDelivery(order)) flow.add(statusOutForDelivery);
    flow.add(statusCompleted);
    return flow;
  }

  /// Full flow including the conditional waiting statuses (for display).
  static List<String> getFullFlow(OrderModel order) {
    final service = resolveServiceType(order);
    final flow = <String>[
      statusOrderReceived,
      statusPaymentPendingVerification,
      statusPaymentVerified,
    ];
    if (needsWashing(service)) {
      flow.add(statusWaitingForMachine);
      flow.add(statusMachineAssigned);
      flow.add(statusWashing);
    }
    if (needsDrying(service)) {
      flow.add(statusWaitingForDryer);
      flow.add(statusDryerAssigned);
      flow.add(statusDrying);
    }
    flow.add(readyStatus(order));
    if (hasDelivery(order)) flow.add(statusOutForDelivery);
    flow.add(statusCompleted);
    return flow;
  }

  /// Current position of the order in its full flow (-1 if not found).
  static int getCurrentIndex(OrderModel order) {
    return getFullFlow(order).indexOf(order.status.value);
  }

  /// Determine the next status a staff member should set, considering
  /// machine availability. Returns null when the order is finished.
  static String? getNextStatus(
    OrderModel order, {
    List<MachineModel>? machines,
  }) {
    final current = order.status.value;
    if (current == 'Cancelled') return null;

    // Waiting states always proceed to Machine Assigned (scheduler reserves).
    if (current == statusWaitingForMachine) return statusMachineAssigned;
    if (current == statusWaitingForDryer) return statusDryerAssigned;

    // Machine Assigned -> staff starts the physical operation.
    if (current == statusMachineAssigned) {
      if (order.assignedMachineType == AppConstants.machineDryer) {
        return statusDrying; // Dry phase (Wash & Dry or Dry Only)
      }
      return statusWashing; // Wash phase
    }

    // Dryer Assigned -> staff starts the drying operation.
    if (current == statusDryerAssigned) return statusDrying;

    final baseFlow = getBaseFlow(order);
    final currentIndex = baseFlow.indexOf(current);
    if (currentIndex < 0) {
      final fullFlow = getFullFlow(order);
      final idx = fullFlow.indexOf(current);
      if (idx >= 0 && idx < fullFlow.length - 1) {
        return fullFlow[idx + 1];
      }
      // Unknown/legacy status (e.g. 'Pending') → start the flow.
      return baseFlow.isNotEmpty ? baseFlow.first : null;
    }
    if (currentIndex >= baseFlow.length - 1) return null;

    final next = baseFlow[currentIndex + 1];

    // Insert a waiting status only when the required machine is unavailable.
    if (next == statusWashing && machines != null) {
      final hasWasher = machines.any(
        (m) =>
            m.type == AppConstants.machineWasher &&
            m.status == AppConstants.machineAvailable,
      );
      if (!hasWasher) return statusWaitingForMachine;
    }
    if (next == statusDrying && machines != null) {
      final hasDryer = machines.any(
        (m) =>
            m.type == AppConstants.machineDryer &&
            m.status == AppConstants.machineAvailable,
      );
      if (!hasDryer) return statusWaitingForDryer;
    }

    return next;
  }

  /// The initial processing status set when payment is approved,
  /// based on service type and current machine availability.
  static String getInitialProcessingStatus(
    String serviceType,
    List<MachineModel> machines,
  ) {
    final service = _normalize(serviceType);
    if (service == serviceDryOnly) {
      final hasDryer = machines.any(
        (m) =>
            m.type == AppConstants.machineDryer &&
            m.status == AppConstants.machineAvailable,
      );
      return hasDryer ? statusMachineAssigned : statusWaitingForDryer;
    }
    final hasWasher = machines.any(
      (m) =>
          m.type == AppConstants.machineWasher &&
          m.status == AppConstants.machineAvailable,
    );
    return hasWasher ? statusMachineAssigned : statusWaitingForMachine;
  }
}
