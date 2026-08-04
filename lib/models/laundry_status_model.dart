enum LaundryStatus {
  pending,
  pendingPayment,
  paid,
  orderReceived,
  paymentPendingVerification,
  paymentVerified,
  waitingForMachine,
  machineAssigned,
  washing,
  waitingForDryer,
  dryerAssigned,
  drying,
  folding,
  readyForDelivery,
  readyForPickup,
  outForDelivery,
  delivered,
  completed,
  cancelled;

  String get value {
    switch (this) {
      case LaundryStatus.pending:
        return 'Pending';
      case LaundryStatus.pendingPayment:
        return 'Pending Payment';
      case LaundryStatus.paid:
        return 'Paid';
      case LaundryStatus.orderReceived:
        return 'Order Received';
      case LaundryStatus.paymentPendingVerification:
        return 'Payment Pending Verification';
      case LaundryStatus.paymentVerified:
        return 'Payment Verified';
      case LaundryStatus.waitingForMachine:
        return 'Waiting for Machine';
      case LaundryStatus.machineAssigned:
        return 'Machine Assigned';
      case LaundryStatus.washing:
        return 'Washing';
      case LaundryStatus.waitingForDryer:
        return 'Waiting for Dryer';
      case LaundryStatus.dryerAssigned:
        return 'Dryer Assigned';
      case LaundryStatus.drying:
        return 'Drying';
      case LaundryStatus.folding:
        return 'Folding';
      case LaundryStatus.readyForDelivery:
        return 'Ready for Delivery';
      case LaundryStatus.readyForPickup:
        return 'Ready for Pickup';
      case LaundryStatus.outForDelivery:
        return 'Out for Delivery';
      case LaundryStatus.delivered:
        return 'Delivered';
      case LaundryStatus.completed:
        return 'Completed';
      case LaundryStatus.cancelled:
        return 'Cancelled';
    }
  }

  static LaundryStatus fromString(String status) {
    switch (status) {
      case 'Pending':
        return LaundryStatus.pending;
      case 'Pending Payment':
        return LaundryStatus.pendingPayment;
      case 'Paid':
        return LaundryStatus.paid;
      case 'Order Received':
        return LaundryStatus.orderReceived;
      case 'Payment Pending Verification':
        return LaundryStatus.paymentPendingVerification;
      case 'Payment Verified':
        return LaundryStatus.paymentVerified;
      case 'Waiting for Machine':
        return LaundryStatus.waitingForMachine;
      case 'Machine Assigned':
        return LaundryStatus.machineAssigned;
      case 'Washing':
        return LaundryStatus.washing;
      case 'Waiting for Dryer':
        return LaundryStatus.waitingForDryer;
      case 'Dryer Assigned':
        return LaundryStatus.dryerAssigned;
      case 'Drying':
        return LaundryStatus.drying;
      case 'Folding':
        return LaundryStatus.folding;
      case 'Ready for Delivery':
        return LaundryStatus.readyForDelivery;
      case 'Ready for Pickup':
        return LaundryStatus.readyForPickup;
      case 'Out for Delivery':
        return LaundryStatus.outForDelivery;
      case 'Delivered':
        return LaundryStatus.delivered;
      case 'Completed':
        return LaundryStatus.completed;
      case 'Cancelled':
        return LaundryStatus.cancelled;
      default:
        return LaundryStatus.pending;
    }
  }

  bool get isProcessing =>
      this == LaundryStatus.orderReceived ||
      this == LaundryStatus.paymentPendingVerification ||
      this == LaundryStatus.paymentVerified ||
      this == LaundryStatus.waitingForMachine ||
      this == LaundryStatus.machineAssigned ||
      this == LaundryStatus.washing ||
      this == LaundryStatus.waitingForDryer ||
      this == LaundryStatus.dryerAssigned ||
      this == LaundryStatus.drying ||
      this == LaundryStatus.folding;

  bool get isDelivering =>
      this == LaundryStatus.readyForDelivery ||
      this == LaundryStatus.readyForPickup ||
      this == LaundryStatus.outForDelivery;

  bool get isFinished =>
      this == LaundryStatus.delivered || this == LaundryStatus.completed;

  static List<LaundryStatus> get staffUpdatableStatuses => [
    LaundryStatus.orderReceived,
    LaundryStatus.washing,
    LaundryStatus.drying,
    LaundryStatus.folding,
    LaundryStatus.readyForDelivery,
    LaundryStatus.readyForPickup,
    LaundryStatus.outForDelivery,
    LaundryStatus.delivered,
    LaundryStatus.completed,
  ];
}
