import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/order_provider.dart';
import 'providers/payment_provider.dart';
import 'providers/service_provider.dart';
import 'providers/delivery_provider.dart';
import 'providers/soap_provider.dart';
import 'providers/machine_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/register_step1_screen.dart';
import 'features/auth/screens/register_step2_location_screen.dart';
import 'features/auth/screens/forgot_password_screen.dart';
import 'features/customer/screens/home_screen.dart';
import 'features/customer/screens/create_order_screen.dart';
import 'features/customer/screens/checkout_screen.dart';
import 'features/customer/screens/payment_screen.dart';
import 'features/customer/screens/gcash_payment_screen.dart';
import 'features/customer/screens/order_history_screen.dart';
import 'features/customer/screens/order_tracking_screen.dart';
import 'features/customer/screens/profile_screen.dart';
import 'features/customer/screens/membership_screen.dart';
import 'features/customer/screens/loyalty_screen.dart';
import 'features/staff/screens/staff_home_screen.dart';
import 'features/staff/screens/laundry_task_screen.dart';
import 'features/staff/screens/weight_verification_screen.dart';
import 'features/staff/screens/machine_monitor_screen.dart';
import 'features/staff/screens/delivery_queue_screen.dart';
import 'features/staff/screens/delivery_staff_home_screen.dart';
import 'features/admin/screens/admin_dashboard_screen.dart';
import 'features/admin/screens/manage_orders_screen.dart';
import 'features/admin/screens/payment_verification_screen.dart';
import 'features/admin/screens/walkin_transaction_screen.dart';
import 'features/admin/screens/reports_screen.dart';
import 'features/admin/screens/admin_soap_inventory_screen.dart';
import 'features/admin/screens/machine_analytics_screen.dart';
import 'features/admin/screens/admin_machine_management_screen.dart';
import 'features/admin/screens/business_configuration_screen.dart';
import 'features/admin/screens/membership_verification_screen.dart';
import 'features/admin/screens/promotion_management_screen.dart';
import 'features/admin/screens/loyalty_reward_management_screen.dart';
import 'features/receipts/receipt_preview_screen.dart';
import 'models/order_model.dart';

class LaundryApp extends StatelessWidget {
  const LaundryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
        ChangeNotifierProvider(create: (_) => PaymentProvider()),
        ChangeNotifierProvider(create: (_) => ServiceProvider()),
        ChangeNotifierProvider(create: (_) => DeliveryProvider()),
        ChangeNotifierProvider(create: (_) => SoapProvider()),
        ChangeNotifierProvider(create: (_) => MachineProvider()),
      ],
      child: MaterialApp(
        title: 'Laundry App',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        initialRoute: '/',
        onGenerateRoute: _generateRoute,
      ),
    );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    switch (settings.name) {
      // Auth Routes
      case '/':
      case '/login':
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case '/register/step1':
        return MaterialPageRoute(builder: (_) => const RegisterStep1Screen());
      case '/register/step2':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => RegisterStep2LocationScreen(
            name: args['name'],
            email: args['email'],
            password: args['password'],
            phone: args['phone'],
          ),
        );
      case '/forgot-password':
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());

      // Customer Routes
      case '/customer/home':
        return MaterialPageRoute(builder: (_) => const CustomerHomeScreen());
      case '/customer/create-order':
        return MaterialPageRoute(builder: (_) => const CreateOrderScreen());
      case '/customer/checkout':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => CheckoutScreen(
            serviceId: args['serviceId'],
            serviceName: args['serviceName'],
            pricePerKg: args['pricePerKg'],
            weight: (args['weight'] ?? 0).toDouble(),
            cycles: (args['cycles'] ?? 0) as int,
            notes: args['notes'] as String? ?? '',
            selectedSoaps:
                (args['selectedSoaps'] as List<dynamic>?)
                    ?.cast<Map<String, dynamic>>() ??
                [],
            soapTotal: (args['soapTotal'] ?? 0).toDouble(),
          ),
        );
      case '/customer/payment':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => PaymentScreen(
            orderId: args['orderId'],
            amount: (args['amount'] ?? 0).toDouble(),
            serviceName: args['serviceName'] ?? '',
            weight: (args['weight'] ?? 0).toDouble(),
            cycles: args['cycles'] ?? 0,
            deliveryFee: (args['deliveryFee'] ?? 0).toDouble(),
            subtotal: (args['subtotal'] ?? 0).toDouble(),
            selectedSoaps:
                (args['selectedSoaps'] as List<dynamic>?)
                    ?.cast<Map<String, dynamic>>() ??
                [],
            soapTotal: (args['soapTotal'] ?? 0).toDouble(),
            deliveryMethod: args['deliveryMethod'] ?? 'Pickup',
          ),
        );
      case '/customer/gcash-payment':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => GCashPaymentScreen(
            orderId: args['orderId'],
            amount: args['amount'],
            paymentType: args['paymentType'] ?? 'laundry',
          ),
        );
      case '/customer/order-history':
        return MaterialPageRoute(builder: (_) => const OrderHistoryScreen());
      case '/customer/order-tracking':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(orderId: args['orderId']),
        );
      case '/receipt-preview':
        final order = settings.arguments as OrderModel;
        return MaterialPageRoute(builder: (_) => ReceiptPreviewScreen(order: order));
      case '/customer/profile':
        return MaterialPageRoute(builder: (_) => const ProfileScreen());
      case '/customer/membership':
        return MaterialPageRoute(builder: (_) => const MembershipScreen());
      case '/customer/loyalty':
        return MaterialPageRoute(builder: (_) => const LoyaltyScreen());

      // Staff Routes
      case '/staff/home':
        return MaterialPageRoute(builder: (_) => const StaffHomeScreen());
      case '/delivery/home':
        return MaterialPageRoute(
          builder: (_) => const DeliveryStaffHomeScreen(),
        );
      case '/staff/laundry-task':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => LaundryTaskScreen(orderId: args['orderId']),
        );
      case '/staff/weight-verification':
        final args = settings.arguments as Map<String, dynamic>;
        return MaterialPageRoute(
          builder: (_) => WeightVerificationScreen(orderId: args['orderId']),
        );
      case '/staff/machines':
        return MaterialPageRoute(builder: (_) => const MachineMonitorScreen());
      case '/staff/delivery-queue':
        return MaterialPageRoute(builder: (_) => const DeliveryQueueScreen());

      // Admin Routes
      case '/admin/dashboard':
        return MaterialPageRoute(builder: (_) => const AdminDashboardScreen());
      case '/admin/orders':
        return MaterialPageRoute(builder: (_) => const ManageOrdersScreen());
      case '/admin/payments':
        return MaterialPageRoute(
          builder: (_) => const PaymentVerificationScreen(),
        );
      case '/admin/walkin':
        return MaterialPageRoute(
          builder: (_) => const WalkinTransactionScreen(),
        );
      case '/admin/reports':
        return MaterialPageRoute(builder: (_) => const ReportsScreen());
      case '/admin/machine-analytics':
        return MaterialPageRoute(
          builder: (_) => const MachineAnalyticsScreen(),
        );
      case '/admin/soaps':
        return MaterialPageRoute(
          builder: (_) => const AdminSoapInventoryScreen(),
        );
      case '/admin/machine-management':
        return MaterialPageRoute(
          builder: (_) => const AdminMachineManagementScreen(),
        );
      case '/admin/business-configuration':
        return MaterialPageRoute(builder: (_) => const BusinessConfigurationScreen());
      case '/admin/membership-verification':
        return MaterialPageRoute(builder: (_) => const MembershipVerificationScreen());
      case '/admin/promotions': return MaterialPageRoute(builder: (_) => const PromotionManagementScreen());
      case '/admin/loyalty-rewards': return MaterialPageRoute(builder: (_) => const LoyaltyRewardManagementScreen());

      default:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
    }
  }
}
