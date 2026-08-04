import 'address_model.dart';
import 'role_model.dart';

class UserModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final AddressModel? address;
  final String? photoUrl;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    this.role = UserRole.customer,
    this.address,
    this.photoUrl,
    this.isActive = true,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'role': role.value,
      'address': address?.toMap(),
      'photoUrl': photoUrl,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    AddressModel? address;
    if (map['address'] != null) {
      if (map['address'] is Map<String, dynamic>) {
        address = AddressModel.fromMap(map['address']);
      } else if (map['address'] is String) {
        // Address stored as plain string (legacy data from registration)
        address = AddressModel(
          street: map['address'] as String,
          barangay: '',
          city: '',
          latitude: (map['latitude'] ?? 0.0).toDouble(),
          longitude: (map['longitude'] ?? 0.0).toDouble(),
        );
      }
    }

    return UserModel(
      id: id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      role: UserRole.fromString(map['role'] ?? 'customer'),
      address: address,
      photoUrl: map['photoUrl'],
      isActive: map['isActive'] ?? true,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'])
          : null,
    );
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? phone,
    AddressModel? address,
    String? photoUrl,
    bool? isActive,
    UserRole? role,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      address: address ?? this.address,
      photoUrl: photoUrl ?? this.photoUrl,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
