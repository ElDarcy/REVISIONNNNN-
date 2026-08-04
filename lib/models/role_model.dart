enum UserRole {
  customer,
  staff,
  laundryStaff,
  deliveryStaff,
  admin;

  String get value {
    switch (this) {
      case UserRole.customer:
        return 'customer';
      case UserRole.staff:
        return 'staff';
      case UserRole.laundryStaff:
        return 'laundry_staff';
      case UserRole.deliveryStaff:
        return 'delivery_staff';
      case UserRole.admin:
        return 'admin';
    }
  }

  static UserRole fromString(String role) {
    switch (role) {
      case 'customer':
        return UserRole.customer;
      case 'staff':
      case 'laundry_staff':
        return UserRole.laundryStaff;
      case 'delivery_staff':
        return UserRole.deliveryStaff;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.customer;
    }
  }
}
