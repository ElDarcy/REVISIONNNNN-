class AppConstants {
  // App Info
  static const String appName = 'Laundry App';
  static const String appVersion = '1.0.0';

  // Shop Information
  static const String shopName = 'Laundry Express';
  static const String shopAddress = 'Sabalo, Brgy. 12, Caloocan City';
  static const String shopPhone = '09932184932';
  static const String shopEmail = 'laundryexpress@gmail.com';

  // Business Hours
  static const String businessOpen = '7:00 AM';
  static const String businessClose = '9:00 PM';
  static const String businessDays = 'Monday - Saturday';

  // Service Types
  static const String serviceWashOnly = 'Wash Only';
  static const String serviceDryOnly = 'Dry Only';
  static const String serviceWashDry = 'Wash and Dry';

  // Order Status Flow
  static const List<String> orderStatusFlow = [
    'Pending Payment',
    'Order Received',
    'Payment Pending Verification',
    'Payment Verified',
    'Waiting for Machine',
    'Washing',
    'Waiting for Dryer',
    'Drying',
    'Folding',
    'Ready for Delivery',
    'Ready for Pickup',
    'Out for Delivery',
    'Delivered',
    'Completed',
  ];

  // Status Colors Mapping
  static const Map<String, int> statusColors = {
    'Pending': 0xFFFFA726,
    'Pending Payment': 0xFFFFA726,
    'Paid': 0xFF42A5F5,
    'Order Received': 0xFF42A5F5,
    'Payment Pending Verification': 0xFFFFA726,
    'Payment Verified': 0xFF42A5F5,
    'Waiting for Machine': 0xFFEF9A9A,
    'Washing': 0xFF29B6F6,
    'Waiting for Dryer': 0xFFEF9A9A,
    'Drying': 0xFF4FC3F7,
    'Folding': 0xFF81D4FA,
    'Ready for Delivery': 0xFF66BB6A,
    'Ready for Pickup': 0xFF66BB6A,
    'Out for Delivery': 0xFF43A047,
    'Delivered': 0xFF388E3C,
    'Completed': 0xFF2E7D32,
    'Cancelled': 0xFFE53935,
  };

  // Machine Types
  static const String machineWasher = 'wash';
  static const String machineDryer = 'dry';
  static const String machineWashLabel = 'Wash';
  static const String machineDryLabel = 'Dry';

  // Machine Statuses
  static const String machineAvailable = 'available';
  static const String machineReserved = 'reserved';
  static const String machineWashing = 'washing';
  static const String machineDrying = 'drying';
  static const String machineMaintenance = 'maintenance';

  // Order Statuses
  static const String statusMachineAssigned = 'Machine Assigned';
  static const String statusDryerAssigned = 'Dryer Assigned';

  // Machine Cycle
  static const int machineCycleMinutes = 38;

  // Machine Counts
  static const int machineWashCount = 9;
  static const int machineDryCount = 9;

  // Machine Log Actions
  static const String machineLogStarted = 'Started';
  static const String machineLogCompleted = 'Completed';
  static const String machineLogReserved = 'Reserved';
  static const String machineLogReleased = 'Released';
  static const String machineLogMaintenance = 'Maintenance';

  // Maintenance threshold (uses) before a machine is recommended for service
  static const int maintenanceThreshold = 200;

  // Delivery Priority Levels
  static const String priorityHigh = 'High';
  static const String priorityMedium = 'Medium';
  static const String priorityLow = 'Low';

  // Notification Types
  static const String notificationOrderUpdate = 'order_update';
  static const String notificationPayment = 'payment';
  static const String notificationDelivery = 'delivery';
  static const String notificationPromo = 'promo';
  static const String notificationGeneral = 'general';
}
