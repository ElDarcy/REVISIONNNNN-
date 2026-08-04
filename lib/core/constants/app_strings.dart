class AppStrings {
  static const String appName = 'Laundry App';

  // Auth
  static const String login = 'Login';
  static const String register = 'Register';
  static const String email = 'Email';
  static const String password = 'Password';
  static const String confirmPassword = 'Confirm Password';
  static const String fullName = 'Full Name';
  static const String phoneNumber = 'Phone Number';
  static const String forgotPassword = 'Forgot Password?';
  static const String noAccount = 'Don\'t have an account?';
  static const String haveAccount = 'Already have an account?';
  static const String loginSuccess = 'Login successful!';
  static const String registerSuccess = 'Registration successful!';
  static const String logout = 'Logout';

  // Location
  static const String enableLocation = 'Enable Location';
  static const String locationRequired = 'Location permission is required';
  static const String gettingLocation = 'Getting your location...';
  static const String locationError = 'Unable to get location';
  static const String outsideCoverage =
      'Sorry, we currently do not deliver to your area.';

  // Customer
  static const String ourServices = 'Our Services';
  static const String createOrder = 'Create Order';
  static const String orderHistory = 'Order History';
  static const String trackOrder = 'Track Order';
  static const String checkout = 'Checkout';
  static const String payment = 'Payment';
  static const String uploadReceipt = 'Upload Receipt';
  static const String paymentSuccess = 'Payment Successful!';

  // Order Status
  static const String pending = 'Pending';
  static const String pendingPayment = 'Pending Payment';
  static const String paid = 'Paid';
  static const String orderReceived = 'Order Received';
  static const String paymentPendingVerification =
      'Payment Pending Verification';
  static const String paymentVerified = 'Payment Verified';
  static const String waitingForMachine = 'Waiting for Machine';
  static const String machineAssigned = 'Machine Assigned';
  static const String washing = 'Washing';
  static const String waitingForDryer = 'Waiting for Dryer';
  static const String drying = 'Drying';
  static const String folding = 'Folding';
  static const String readyForDelivery = 'Ready for Delivery';
  static const String readyForPickup = 'Ready for Pickup';
  static const String outForDelivery = 'Out for Delivery';
  static const String delivered = 'Delivered';
  static const String completed = 'Completed';
  static const String cancelled = 'Cancelled';

  // Staff
  static const String assignedTasks = 'Assigned Tasks';
  static const String updateStatus = 'Update Status';
  static const String deliveryQueue = 'Delivery Queue';
  static const String machineMonitor = 'Machine Monitor';

  // Admin
  static const String dashboard = 'Dashboard';
  static const String manageUsers = 'Manage Users';
  static const String manageOrders = 'Manage Orders';
  static const String verifyPayments = 'Verify Payments';
  static const String transactions = 'Transactions';
  static const String walkinTransaction = 'Walk-in Transaction';
  static const String reports = 'Reports';
  static const String printReceipt = 'Print Receipt';

  // General
  static const String save = 'Save';
  static const String cancel = 'Cancel';
  static const String delete = 'Delete';
  static const String edit = 'Edit';
  static const String submit = 'Submit';
  static const String confirm = 'Confirm';
  static const String loading = 'Loading...';
  static const String error = 'Error';
  static const String success = 'Success';
  static const String warning = 'Warning';
  static const String noData = 'No data available';
  static const String retry = 'Retry';
  static const String search = 'Search';
  static const String filter = 'Filter';
  static const String sort = 'Sort';
  static const String total = 'Total';
  static const String amount = 'Amount';
  static const String status = 'Status';
  static const String date = 'Date';
  static const String time = 'Time';

  // Delivery
  static const String deliveryFee = 'Delivery Fee';
  static const String deliveryAddress = 'Delivery Address';
  static const String estimatedDelivery = 'Estimated Delivery';

  // Payment
  static const String gcash = 'GCash';
  static const String cash = 'Cash';
  static const String gcashNumber = 'GCash Number: 09932184932';
  static const String gcashName = 'Account Name: Laundry Service';
  static const String referenceNumber = 'Reference Number';
  static const String uploadScreenshot = 'Upload Payment Screenshot';

  // Validation
  static const String requiredField = 'This field is required';
  static const String invalidEmail = 'Please enter a valid email';
  static const String invalidPhone = 'Please enter a valid phone number';
  static const String passwordTooShort =
      'Password must be at least 6 characters';
  static const String passwordsNotMatch = 'Passwords do not match';
  static const String invalidWeight = 'Please enter a valid weight';

  // Services
  static const String washDry = 'Wash & Dry';
  static const String washDryFold = 'Wash, Dry & Fold';
  static const String dryClean = 'Dry Clean';
  static const String ironOnly = 'Iron Only';
  static const String perKilo = 'per kilo';
  static const String perItem = 'per item';
}
