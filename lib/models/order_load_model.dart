import 'package:cloud_firestore/cloud_firestore.dart';
import 'laundry_status_model.dart';

/// A single laundry load that belongs to a parent [OrderModel].
///
/// When an order's total weight exceeds the machine capacity (8kg per load),
/// the order is divided into multiple loads:
///
///   numberOfLoads = ceil(totalWeight / 8)
///
/// Each load lives in the `orderLoads` collection and is assigned machines
/// independently. The parent order status is derived from the statuses of all
/// its loads.
class OrderLoadModel {
  final String id; // loadId
  final String orderId;
  final int loadNumber; // 1-based load number within the order
  final double weight; // kg for this load (max 8kg, last may be less)
  final String serviceType; // 'Wash Only' | 'Dry Only' | 'Wash and Dry'
  final String? machineType; // 'wash' | 'dry' (null until assigned)
  final String? machineId; // e.g. wash_01 (null until assigned)
  final int? machineNumber; // 1..9 (null until assigned)
  final LaundryStatus status;
  final DateTime? cycleStart;
  final DateTime? estimatedFinish;
  final DateTime createdAt;
  final DateTime? updatedAt;

  OrderLoadModel({
    required this.id,
    required this.orderId,
    required this.loadNumber,
    required this.weight,
    required this.serviceType,
    this.machineType,
    this.machineId,
    this.machineNumber,
    this.status = LaundryStatus.paymentVerified,
    this.cycleStart,
    this.estimatedFinish,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get loadLabel => 'Load ${loadNumber}';

  Map<String, dynamic> toMap() {
    return {
      'loadId': id,
      'orderId': orderId,
      'loadNumber': loadNumber,
      'weight': weight,
      'serviceType': serviceType,
      'machineType': machineType,
      'machineId': machineId,
      'machineNumber': machineNumber,
      'status': status.value,
      'cycleStart': cycleStart?.toIso8601String(),
      'estimatedFinish': estimatedFinish?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory OrderLoadModel.fromMap(Map<String, dynamic> map, String id) {
    return OrderLoadModel(
      id: id,
      orderId: map['orderId'] ?? '',
      loadNumber: (map['loadNumber'] ?? 1).toInt(),
      weight: (map['weight'] ?? 0).toDouble(),
      serviceType: map['serviceType'] ?? 'Wash and Dry',
      machineType: map['machineType'],
      machineId: map['machineId'] ?? map['assignedMachineId'],
      machineNumber:
          (map['machineNumber'] as num?)?.toInt() ??
          (map['assignedMachineNumber'] as num?)?.toInt(),
      status: LaundryStatus.fromString(map['status'] ?? 'Payment Verified'),
      cycleStart: _parseDate(map['cycleStart']),
      estimatedFinish: _parseDate(map['estimatedFinish']),
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  /// Parses a date that may be a Firestore [Timestamp], a [DateTime], or an
  /// ISO-8601 [String]. Returns null when the value is null or unparseable.
  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
