import 'package:flutter/material.dart';

class AppRoutes {
  static const String login = '/login';
  static const String registerStep1 = '/register/step1';
  static const String registerStep2 = '/register/step2';
  static const String forgotPassword = '/forgot-password';

  // Customer
  static const String customerHome = '/customer/home';
  static const String customerProfile = '/customer/profile';
  static const String createOrder = '/customer/create-order';
  static const String serviceSelection = '/customer/select-service';
  static const String checkout = '/customer/checkout';
  static const String deliveryFee = '/customer/delivery-fee';
  static const String payment = '/customer/payment';
  static const String gcashPayment = '/customer/gcash-payment';
  static const String uploadReceipt = '/customer/upload-receipt';
  static const String paymentSuccess = '/customer/payment-success';
  static const String orderHistory = '/customer/order-history';
  static const String orderTracking = '/customer/order-tracking';
  static const String receiptView = '/customer/receipt';

  // Staff
  static const String staffHome = '/staff/home';
  static const String laundryTask = '/staff/laundry-task';
  static const String machineMonitor = '/staff/machines';
  static const String deliveryQueue = '/staff/delivery-queue';
  static const String deliveryStatus = '/staff/delivery-status';

  // Admin
  static const String adminDashboard = '/admin/dashboard';
  static const String manageUsers = '/admin/users';
  static const String manageOrders = '/admin/orders';
  static const String paymentVerification = '/admin/payments';
  static const String transactions = '/admin/transactions';
  static const String walkinTransaction = '/admin/walkin';
  static const String deliveryMonitor = '/admin/delivery-monitor';
  static const String reports = '/admin/reports';
  static const String machineAnalytics = '/admin/machine-analytics';
  static const String receiptPrint = '/admin/print-receipt';
  static const String soapInventory = '/admin/soaps';

  static Map<String, WidgetBuilder> routes = {};

  static void generateRoutes() {
    // Will be populated when screens are created
  }
}
