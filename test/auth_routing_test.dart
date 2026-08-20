import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_app/engines/auth_routing.dart';
import 'package:laundry_app/models/address_model.dart';
import 'package:laundry_app/models/role_model.dart';
import 'package:laundry_app/models/user_model.dart';

UserModel _user(UserRole role, {AddressModel? address}) => UserModel(
      id: 'u1',
      name: 'Test',
      email: 't@t.com',
      phone: '',
      role: role,
      address: address,
    );

AddressModel _completeAddress() => AddressModel(
      street: 'San Jose Street',
      barangay: 'Poblacion',
      city: 'Mabini',
      province: 'Batangas',
      latitude: 13.75,
      longitude: 120.94,
    );

void main() {
  group('AuthRouting.routeFor', () {
    test('admin goes to admin dashboard', () {
      expect(AuthRouting.routeFor(_user(UserRole.admin)), '/admin/dashboard');
    });

    test('staff goes to staff home', () {
      expect(AuthRouting.routeFor(_user(UserRole.staff)), '/staff/home');
      expect(AuthRouting.routeFor(_user(UserRole.laundryStaff)), '/staff/home');
    });

    test('delivery staff goes to delivery home', () {
      expect(
        AuthRouting.routeFor(_user(UserRole.deliveryStaff)),
        '/delivery/home',
      );
    });

    test('customer with incomplete location goes to Location Setup', () {
      expect(
        AuthRouting.routeFor(_user(UserRole.customer)),
        '/customer/location-setup',
      );
    });

    test('customer with complete location goes to dashboard', () {
      final customer = _user(UserRole.customer, address: _completeAddress());
      expect(AuthRouting.routeFor(customer), '/customer/home');
    });
  });
}