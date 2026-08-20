import '../models/user_model.dart';
import '../models/role_model.dart';

import 'customer_location_gate.dart';

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