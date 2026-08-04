class AddressModel {
  final String street;
  final String barangay;
  final String city;
  final double latitude;
  final double longitude;
  final bool isDefault;

  AddressModel({
    required this.street,
    required this.barangay,
    required this.city,
    required this.latitude,
    required this.longitude,
    this.isDefault = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'street': street,
      'barangay': barangay,
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
      'isDefault': isDefault,
    };
  }

  factory AddressModel.fromMap(Map<String, dynamic> map) {
    return AddressModel(
      street: map['street'] ?? '',
      barangay: map['barangay'] ?? '',
      city: map['city'] ?? '',
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      isDefault: map['isDefault'] ?? false,
    );
  }

  String get fullAddress => '$street, $barangay, $city';
}
