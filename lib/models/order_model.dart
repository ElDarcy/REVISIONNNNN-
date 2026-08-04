import 'package:cloud_firestore/cloud_firestore.dart';
import 'address_model.dart';
import 'order_item_model.dart';
import 'laundry_status_model.dart';

class OrderModel {
  final String id;
  final String userId;
  final String? staffId;
  // Order source: 'online' | 'walk_in'
  final String? orderType;
  // Creator uid (admin/laundry staff) for walk-in orders
  final String? createdBy;
  final String? customerId; // null for walk-in (no auth user)
  final String? customerName;
  final String? customerPhone;
  // Cycle timing - set ONLY when staff starts washing/drying
  final DateTime? cycleStart;
  final DateTime? estimatedFinish;
  final List<OrderItemModel> items;
  final double weight;
  final double subtotal;
  final double deliveryFee;
  final double totalAmount;
  final LaundryStatus status;
  final String paymentMethod;
  final String paymentStatus;
  final String? serviceType; // 'Wash Only', 'Dry Only', 'Wash and Dry'
  final String deliveryMethod; // 'Pickup' or 'Drop-off'
  final AddressModel? deliveryAddress;
  final double? customerLatitude;
  final double? customerLongitude;
  final double? distanceKm;
  final String? notes;
  final String? assignedTo;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final DateTime? approvedAt;
  final int? estimatedDuration;
  final DateTime? estimatedFinishTime;
  // Machine assignment fields (set when staff starts a machine)
  final String? assignedMachineId; // e.g. wash_03
  final String? assignedMachineType; // 'wash' | 'dry'
  final int? assignedMachineNumber; // 1..9
  // History of machines used by this order (e.g. wash_03 then dry_05)
  final List<Map<String, dynamic>> machineHistory;
  // Number of loads this order is split into (when weight exceeds 8kg).
  // Each load is a separate record in the `orderLoads` collection.
  final int? numberOfLoads;

  OrderModel({
    required this.id,
    required this.userId,
    this.staffId,
    this.orderType,
    this.createdBy,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.cycleStart,
    this.estimatedFinish,
    this.items = const [],
    this.weight = 0,
    this.subtotal = 0,
    this.deliveryFee = 0,
    this.totalAmount = 0,
    this.status = LaundryStatus.pending,
    this.paymentMethod = 'GCash',
    this.paymentStatus = 'Pending Verification',
    this.serviceType,
    this.deliveryMethod = 'Pickup',
    this.deliveryAddress,
    this.customerLatitude,
    this.customerLongitude,
    this.distanceKm,
    this.notes,
    this.assignedTo,
    this.rejectionReason,
    DateTime? createdAt,
    this.updatedAt,
    this.completedAt,
    this.approvedAt,
    this.estimatedDuration,
    this.estimatedFinishTime,
    this.assignedMachineId,
    this.assignedMachineType,
    this.assignedMachineNumber,
    this.machineHistory = const [],
    this.numberOfLoads,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'staffId': staffId,
      'orderType': orderType,
      'createdBy': createdBy,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'cycleStart': cycleStart?.toIso8601String(),
      'estimatedFinish': estimatedFinish?.toIso8601String(),
      'items': items.map((item) => item.toMap()).toList(),
      'weight': weight,
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'totalAmount': totalAmount,
      'status': status.value,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'serviceType': serviceType,
      'deliveryMethod': deliveryMethod,
      'deliveryAddress': deliveryAddress?.toMap(),
      'customerLatitude': customerLatitude,
      'customerLongitude': customerLongitude,
      'distanceKm': distanceKm,
      'notes': notes,
      'assignedTo': assignedTo,
      'rejectionReason': rejectionReason,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'approvedAt': approvedAt?.toIso8601String(),
      'estimatedDuration': estimatedDuration,
      'estimatedFinishTime': estimatedFinishTime?.toIso8601String(),
      'assignedMachineId': assignedMachineId,
      'assignedMachineType': assignedMachineType,
      'assignedMachineNumber': assignedMachineNumber,
      'machineHistory': machineHistory,
      'numberOfLoads': numberOfLoads,
    };
  }

  factory OrderModel.fromMap(Map<String, dynamic> map, String id) {
    return OrderModel(
      id: id,
      userId: map['userId'] ?? '',
      staffId: map['staffId'],
      orderType: map['orderType'],
      createdBy: map['createdBy'],
      customerId: map['customerId'],
      customerName: map['customerName'],
      customerPhone: map['customerPhone'],
      cycleStart: _parseDate(map['cycleStart']),
      estimatedFinish: _parseDate(map['estimatedFinish']),
      items:
          (map['items'] as List<dynamic>?)
              ?.map((e) => OrderItemModel.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      weight: (map['weight'] ?? 0).toDouble(),
      subtotal: (map['subtotal'] ?? 0).toDouble(),
      deliveryFee: (map['deliveryFee'] ?? 0).toDouble(),
      totalAmount: (map['totalAmount'] ?? 0).toDouble(),
      status: LaundryStatus.fromString(map['status'] ?? 'Pending'),
      paymentMethod: map['paymentMethod'] ?? 'GCash',
      paymentStatus: map['paymentStatus'] ?? 'Pending Verification',
      serviceType: map['serviceType'],
      deliveryMethod: map['deliveryMethod'] ?? 'Pickup',
      deliveryAddress: map['deliveryAddress'] != null
          ? AddressModel.fromMap(map['deliveryAddress'])
          : null,
      customerLatitude: (map['customerLatitude']?.toDouble()),
      customerLongitude: (map['customerLongitude']?.toDouble()),
      distanceKm: (map['distanceKm']?.toDouble()),
      notes: map['notes'],
      assignedTo: map['assignedTo'],
      rejectionReason: map['rejectionReason'],
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updatedAt']),
      completedAt: _parseDate(map['completedAt']),
      approvedAt: _parseDate(map['approvedAt']),
      estimatedDuration: (map['estimatedDuration'] as num?)?.toInt(),
      estimatedFinishTime: _parseDate(map['estimatedFinishTime']),
      assignedMachineId: map['assignedMachineId'],
      assignedMachineType: map['assignedMachineType'],
      assignedMachineNumber: (map['assignedMachineNumber'] as num?)?.toInt(),
      machineHistory:
          (map['machineHistory'] as List<dynamic>?)
              ?.map((e) => (e as Map).cast<String, dynamic>())
              .toList() ??
          const [],
      numberOfLoads: (map['numberOfLoads'] as num?)?.toInt(),
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
