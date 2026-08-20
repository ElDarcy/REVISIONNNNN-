class AppConfig {
  static const String appName = 'Laundry App';
  static const String appVersion = '1.0.0';

  // Shop Location - Sabalo, Brgy. 12, Caloocan City
  static const double shopLatitude = 14.653173;
  static const double shopLongitude = 120.967443;
  static const String shopAddress = 'Sabalo, Brgy. 12, Caloocan City';

  // Delivery
  static const double maxDeliveryRadiusKm = 15.0;
  static const double deliveryBaseFee = 20.0;
  static const double deliveryPerKmFee = 10.0;

  // GCash
  static const String gcashNumber = '09932184932';
  static const String gcashAccountName = 'Laundry Service';

  // Firebase Collections
  static const String usersCollection = 'users';
  static const String ordersCollection = 'orders';
  static const String servicesCollection = 'services';
  static const String paymentsCollection = 'payments';
  static const String transactionsCollection = 'transactions';
  static const String deliveriesCollection = 'deliveries';
  static const String machinesCollection = 'machines';
  static const String notificationsCollection = 'notifications';
  static const String promosCollection = 'promos';
  static const String receiptsCollection = 'receipts';

  // Order Statuses
  static const String statusPending = 'Pending';
  static const String statusPaymentPending = 'Pending Payment';
  static const String statusPaid = 'Paid';
  static const String statusReceived = 'Order Received';
  static const String statusPaymentPendingVerification =
      'Payment Pending Verification';
  static const String statusPaymentVerified = 'Payment Verified';
  static const String statusWaitingForMachine = 'Waiting for Machine';
  static const String statusMachineAssigned = 'Machine Assigned';
  static const String statusWashing = 'Washing';
  static const String statusWaitingForDryer = 'Waiting for Dryer';
  static const String statusDrying = 'Drying';
  static const String statusFolding = 'Folding';
  static const String statusReadyForDelivery = 'Ready for Delivery';
  static const String statusReadyForPickup = 'Ready for Pickup';
  static const String statusOutForDelivery = 'Out for Delivery';
  static const String statusDelivered = 'Delivered';
  static const String statusCompleted = 'Completed';
  static const String statusCancelled = 'Cancelled';

  // Order Status Flow (ordered for progress tracking)
  static List<String> get orderStatusFlow => [
    statusPending,
    statusPaymentPending,
    statusPaid,
    statusReceived,
    statusPaymentPendingVerification,
    statusPaymentVerified,
    statusWaitingForMachine,
    statusWashing,
    statusWaitingForDryer,
    statusDrying,
    statusFolding,
    statusReadyForDelivery,
    statusReadyForPickup,
    statusOutForDelivery,
    statusDelivered,
    statusCompleted,
  ];

  // Roles
  static const String roleCustomer = 'customer';
  static const String roleStaff = 'staff';
  static const String roleAdmin = 'admin';

  // Payment Methods
  static const String paymentGCash = 'GCash';
  static const String paymentCash = 'Cash';

  // Payment Statuses
  static const String paymentPending = 'Pending Verification';
  static const String paymentPendingCollection = 'Pending Collection';
  static const String paymentApproved = 'Approved';
  static const String paymentVerified = 'Verified';
  static const String paymentRejected = 'Rejected';

  // Remittance Statuses
  static const String remittancePending = 'Pending Remittance';
  static const String remittanceConfirmed = 'Remitted';

  /// Whether the payment method is cash-based (not GCash).
  static bool isCashMethod(String? method) =>
      method == 'Cash on Pickup' ||
      method == 'Cash at Shop' ||
      method == 'Cash on Drop off';
}
