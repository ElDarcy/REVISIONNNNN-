class AddressModel {
  final String street;
  final String barangay;
  final String city;
  final double latitude;
  final double longitude;
  final bool isDefault;

  // Additive structured fields for the Thia & Nicole delivery location.
  final String houseUnit;
  final String province;
  final String postalCode;
  final String formattedAddress;

  AddressModel({
    required this.street,
    required this.barangay,
    required this.city,
    required this.latitude,
    required this.longitude,
    this.isDefault = false,
    this.houseUnit = '',
    this.province = '',
    this.postalCode = '',
    this.formattedAddress = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'houseUnit': houseUnit,
      'street': street,
      'barangay': barangay,
      'city': city,
      'province': province,
      'postalCode': postalCode,
      'latitude': latitude,
      'longitude': longitude,
      'isDefault': isDefault,
      'formattedAddress': formattedAddress,
    };
  }

  factory AddressModel.fromMap(Map<String, dynamic> map) {
    return AddressModel(
      houseUnit: map['houseUnit'] ?? '',
      street: map['street'] ?? '',
      barangay: map['barangay'] ?? '',
      city: map['city'] ?? '',
      province: map['province'] ?? '',
      postalCode: map['postalCode'] ?? '',
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      isDefault: map['isDefault'] ?? false,
      formattedAddress: map['formattedAddress'] ?? '',
    );
  }

  /// Human-readable one-line address.
  String get fullAddress {
    final parts = <String>[];
    final houseAndStreet = [houseUnit, street]
        .where((part) => part.trim().isNotEmpty)
        .join(' ');
    if (houseAndStreet.trim().isNotEmpty) parts.add(houseAndStreet.trim());
    if (barangay.trim().isNotEmpty) parts.add(barangay.trim());
    final cityProvince = [city, province]
        .where((part) => part.trim().isNotEmpty)
        .join(', ');
    if (cityProvince.trim().isNotEmpty) parts.add(cityProvince.trim());
    if (postalCode.trim().isNotEmpty) parts.add(postalCode.trim());
    return parts.join(', ');
  }

  /// Whether the coordinate pair is usable for navigation.
  bool get hasUsableCoordinates =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude != 0 &&
      longitude != 0;
}