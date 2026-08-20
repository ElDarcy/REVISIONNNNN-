import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_app/engines/customer_location_gate.dart';
import 'package:laundry_app/models/address_model.dart';
import 'package:laundry_app/models/role_model.dart';
import 'package:laundry_app/models/user_model.dart';

UserModel _user({AddressModel? address}) => UserModel(
      id: 'u1',
      name: 'Test',
      email: 't@t.com',
      phone: '',
      role: UserRole.customer,
      address: address,
    );

AddressModel _completeAddress() => AddressModel(
      houseUnit: '12A',
      street: 'San Jose Street',
      barangay: 'Poblacion',
      city: 'Mabini',
      province: 'Batangas',
      postalCode: '4202',
      latitude: 13.75,
      longitude: 120.94,
      formattedAddress: '12A San Jose Street, Poblacion, Mabini, Batangas 4202',
    );

void main() {
  group('CustomerLocationGate.isLocationComplete', () {
    test('false when no address at all', () {
      expect(CustomerLocationGate.isLocationComplete(_user()), isFalse);
    });

    test('false when all required fields are missing', () {
      final user = _user(
        address: AddressModel(
          street: '',
          barangay: '',
          city: '',
          latitude: 0,
          longitude: 0,
        ),
      );
      expect(CustomerLocationGate.isLocationComplete(user), isFalse);
    });

    test('false when only address text is present (no coords)', () {
      final user = _user(
        address:  AddressModel(
          street: 'San Jose Street',
          barangay: 'Poblacion',
          city: 'Mabini',
          province: 'Batangas',
          latitude: 0,
          longitude: 0,
        ),
      );
      expect(CustomerLocationGate.isLocationComplete(user), isFalse);
    });

    test('false when house or street is missing', () {
      final user = _user(
        address: AddressModel(
          street: '',
          barangay: 'Poblacion',
          city: 'Mabini',
          province: 'Batangas',
          latitude: 13.75,
          longitude: 120.94,
        ),
      );
      expect(CustomerLocationGate.isLocationComplete(user), isFalse);
    });

    test('false when barangay is missing', () {
      final user = _user(
        address: AddressModel(
          street: 'San Jose Street',
          barangay: '',
          city: 'Mabini',
          province: 'Batangas',
          latitude: 13.75,
          longitude: 120.94,
        ),
      );
      expect(CustomerLocationGate.isLocationComplete(user), isFalse);
    });

    test('false when province is missing', () {
      final user = _user(
        address: AddressModel(
          street: 'San Jose Street',
          barangay: 'Poblacion',
          city: 'Mabini',
          province: '',
          latitude: 13.75,
          longitude: 120.94,
        ),
      );
      expect(CustomerLocationGate.isLocationComplete(user), isFalse);
    });

    test('false when coordinates are the origin sentinel (0,0)', () {
      final user = _user(
        address: AddressModel(
          street: 'San Jose Street',
          barangay: 'Poblacion',
          city: 'Mabini',
          province: 'Batangas',
          latitude: 0,
          longitude: 0,
        ),
      );
      expect(CustomerLocationGate.isLocationComplete(user), isFalse);
    });

    test('true for a complete address with usable coordinates', () {
      expect(
        CustomerLocationGate.isLocationComplete(_user(address: _completeAddress())),
        isTrue,
      );
    });

    test('house unit alone satisfies the street requirement', () {
      final user = _user(
        address: AddressModel(
          houseUnit: '12A',
          street: '',
          barangay: 'Poblacion',
          city: 'Mabini',
          province: 'Batangas',
          latitude: 13.75,
          longitude: 120.94,
        ),
      );
      expect(CustomerLocationGate.isLocationComplete(user), isTrue);
    });
  });

  group('CustomerLocationGate.missingFields', () {
    test('reports "Delivery location" when no address exists', () {
      expect(CustomerLocationGate.missingFields(_user()), ['Delivery location']);
    });

    test('reports every missing field', () {
      final user = _user(
        address: AddressModel(
          street: '',
          barangay: '',
          city: '',
          province: '',
          latitude: 0,
          longitude: 0,
        ),
      );
      final missing = CustomerLocationGate.missingFields(user);
      expect(missing, containsAll(['House/Unit/Street', 'Barangay', 'City/Municipality', 'Province', 'Coordinates']));
    });

    test('empty when the location is complete', () {
      expect(
        CustomerLocationGate.missingFields(_user(address: _completeAddress())),
        isEmpty,
      );
    });
  });
}