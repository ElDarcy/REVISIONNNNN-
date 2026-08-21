import 'package:cloud_firestore/cloud_firestore.dart';

import 'address_model.dart';
import 'role_model.dart';

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  return null;
}

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
      final rawAddress = map['address'];
      if (rawAddress is Map) {
        address = AddressModel.fromMap(Map<String, dynamic>.from(rawAddress));
      } else if (rawAddress is String) {
        // Address stored as plain string (legacy data from registration)
        address = AddressModel(
          street: rawAddress,
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
      createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updatedAt']),
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
