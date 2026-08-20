import '../models/user_model.dart';
import '../services/location_service.dart';

/// Determines whether a customer has completed delivery location setup.
///
/// This is a read-only gate. It never writes to `users/{uid}` — location data
/// is only written when the customer explicitly completes or edits Location
/// Setup.
class CustomerLocationGate {
  /// A customer location is complete only when the full address AND usable
  /// coordinates are present. The 15 km service-area check is applied at
  /// Location Setup time (see ServiceAreaEngine).
  static bool isLocationComplete(UserModel user) {
    final address = user.address;
    if (address == null) return false;
    return _hasHouseOrStreet(address.houseUnit, address.street) &&
        _hasText(address.barangay) &&
        _hasText(address.city) &&
        _hasText(address.province) &&
        LocationService.isValidCoordinate(address.latitude, address.longitude);
  }

  /// Human-readable list of missing location fields, for messaging.
  static List<String> missingFields(UserModel user) {
    final address = user.address;
    final missing = <String>[];
    if (address == null) {
      return const ['Delivery location'];
    }
    if (!_hasHouseOrStreet(address.houseUnit, address.street)) {
      missing.add('House/Unit/Street');
    }
    if (!_hasText(address.barangay)) missing.add('Barangay');
    if (!_hasText(address.city)) missing.add('City/Municipality');
    if (!_hasText(address.province)) missing.add('Province');
    if (!LocationService.isValidCoordinate(address.latitude, address.longitude)) {
      missing.add('Coordinates');
    }
    return missing;
  }

  static bool _hasText(String value) => value.trim().isNotEmpty;

  static bool _hasHouseOrStreet(String houseUnit, String street) =>
      houseUnit.trim().isNotEmpty || street.trim().isNotEmpty;
}