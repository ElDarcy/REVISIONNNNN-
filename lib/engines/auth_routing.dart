import '../models/user_model.dart';
import '../models/role_model.dart';
import 'customer_location_gate.dart';

/// Pure routing decision from a loaded user to the correct start screen.
///
/// Customers with an incomplete delivery location are sent to Location Setup
/// first, then the dashboard.
class AuthRouting {
  static String routeFor(UserModel user) {
    switch (user.role) {
      case UserRole.admin:
        return '/admin/dashboard';
      case UserRole.staff:
      case UserRole.laundryStaff:
        return '/staff/home';
      case UserRole.deliveryStaff:
        return '/delivery/home';
      case UserRole.customer:
        return CustomerLocationGate.isLocationComplete(user)
            ? '/customer/home'
            : '/customer/location-setup';
    }
  }
}