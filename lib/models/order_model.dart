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
  // Professional sequential number (e.g. LT-2026-0001)
  final String? transactionNumber;
  /// Opaque, optional token used only by the read-only public QR tracker.
  final String? publicTrackingToken;
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
  /// Customer-entered weight, retained when [weight] becomes the verified one.
  final double? estimatedWeight;
  final double? actualWeight;
  /// `pending`, `submitted`, `verified`, or `rejected`. Null means legacy.
  final String? weightStatus;
  /// Firestore document ID in `transaction_proofs` for new Base64 proofs.
  /// Legacy URL proofs remain in [weightEvidenceUrl].
  final String? weightProofId;
  final String? weightEvidenceUrl;
  final String? weightSubmittedBy;
  final DateTime? weightSubmittedAt;
  final String? weightVerifiedBy;
  final DateTime? weightVerifiedAt;
  final String? weightVerificationNote;
  final double subtotal;
  final double deliveryFee;
  final double totalAmount;
  final double? soapTotal;
  final List<Map<String, dynamic>>? selectedSoaps;
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
  final String? assignedDeliveryStaffId;
  final String? collectedBy;
  final DateTime? collectedAt;
  final String? receivedBy;
  final DateTime? receivedAt;
  final String? cashCollectedBy;
  final DateTime? cashCollectedAt;
  final double? cashCollectedAmount;
  final String? cashReceivedBy;
  final DateTime? cashReceivedAt;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final DateTime? approvedAt;
  final DateTime? readyForPickupAt;
  final DateTime? pickupDeadlineAt;
  final String? deliveryRequestStatus;
  final String? deliveryRequestSource;
  final String? deliveryRequestId;
  final DateTime? deliveryRequestedAt;
  final DateTime? deliveryDeadlineAt;
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
  final bool soapDeducted;
  final DateTime? inventoryDeductedAt;

  OrderModel({
    required this.id,
    required this.userId,
    this.staffId,
    this.orderType,
    this.transactionNumber,
    this.publicTrackingToken,
    this.createdBy,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.cycleStart,
    this.estimatedFinish,
    this.items = const [],
    this.weight = 0,
    this.estimatedWeight,
    this.actualWeight,
    this.weightStatus,
    this.weightProofId,
    this.weightEvidenceUrl,
    this.weightSubmittedBy,
    this.weightSubmittedAt,
    this.weightVerifiedBy,
    this.weightVerifiedAt,
    this.weightVerificationNote,
    this.subtotal = 0,
    this.deliveryFee = 0,
    this.totalAmount = 0,
    this.soapTotal,
    this.selectedSoaps,
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
    this.assignedDeliveryStaffId,
    this.collectedBy,
    this.collectedAt,
    this.receivedBy,
    this.receivedAt,
    this.cashCollectedBy,
    this.cashCollectedAt,
    this.cashCollectedAmount,
    this.cashReceivedBy,
    this.cashReceivedAt,
    this.rejectionReason,
    DateTime? createdAt,
    this.updatedAt,
    this.completedAt,
    this.approvedAt,
    this.readyForPickupAt,
    this.pickupDeadlineAt,
    this.deliveryRequestStatus,
    this.deliveryRequestSource,
    this.deliveryRequestId,
    this.deliveryRequestedAt,
    this.deliveryDeadlineAt,
    this.estimatedDuration,
    this.estimatedFinishTime,
    this.assignedMachineId,
    this.assignedMachineType,
    this.assignedMachineNumber,
    this.machineHistory = const [],
    this.numberOfLoads,
    this.soapDeducted = false,
    this.inventoryDeductedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'staffId': staffId,
      'orderType': orderType,
      'transactionNumber': transactionNumber,
      'publicTrackingToken': publicTrackingToken,
      'createdBy': createdBy,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'cycleStart': cycleStart?.toIso8601String(),
      'estimatedFinish': estimatedFinish?.toIso8601String(),
      'items': items.map((item) => item.toMap()).toList(),
      'weight': weight,
      'estimatedWeight': estimatedWeight,
      'actualWeight': actualWeight,
      'weightStatus': weightStatus,
      'weightProofId': weightProofId,
      'weightEvidenceUrl': weightEvidenceUrl,
      'weightSubmittedBy': weightSubmittedBy,
      'weightSubmittedAt': weightSubmittedAt?.toIso8601String(),
      'weightVerifiedBy': weightVerifiedBy,
      'weightVerifiedAt': weightVerifiedAt?.toIso8601String(),
      'weightVerificationNote': weightVerificationNote,
      'subtotal': subtotal,
      'soapTotal': soapTotal,
      'selectedSoaps': selectedSoaps,
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
      'assignedDeliveryStaffId': assignedDeliveryStaffId,
      'collectedBy': collectedBy,
      'collectedAt': collectedAt?.toIso8601String(),
      'receivedBy': receivedBy,
      'receivedAt': receivedAt?.toIso8601String(),
      'cashCollectedBy': cashCollectedBy,
      'cashCollectedAt': cashCollectedAt?.toIso8601String(),
      'cashCollectedAmount': cashCollectedAmount,
      'cashReceivedBy': cashReceivedBy,
      'cashReceivedAt': cashReceivedAt?.toIso8601String(),
      'rejectionReason': rejectionReason,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'approvedAt': approvedAt?.toIso8601String(),
      'readyForPickupAt': readyForPickupAt?.toIso8601String(),
      'pickupDeadlineAt': pickupDeadlineAt?.toIso8601String(),
      'deliveryRequestStatus': deliveryRequestStatus,
      'deliveryRequestSource': deliveryRequestSource,
      'deliveryRequestId': deliveryRequestId,
      'deliveryRequestedAt': deliveryRequestedAt?.toIso8601String(),
      'deliveryDeadlineAt': deliveryDeadlineAt?.toIso8601String(),
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
      transactionNumber: map['transactionNumber'],
      publicTrackingToken: map['publicTrackingToken'],
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
      estimatedWeight: (map['estimatedWeight'] as num?)?.toDouble(),
      actualWeight: (map['actualWeight'] as num?)?.toDouble(),
      weightStatus: map['weightStatus'],
      weightProofId: map['weightProofId'],
      weightEvidenceUrl: map['weightEvidenceUrl'],
      weightSubmittedBy: map['weightSubmittedBy'],
      weightSubmittedAt: _parseDate(map['weightSubmittedAt']),
      weightVerifiedBy: map['weightVerifiedBy'],
      weightVerifiedAt: _parseDate(map['weightVerifiedAt']),
      weightVerificationNote: map['weightVerificationNote'],
      subtotal: (map['subtotal'] ?? 0).toDouble(),
      soapTotal: (map['soapTotal'] as num?)?.toDouble(),
      selectedSoaps: (map['selectedSoaps'] as List<dynamic>?)
          ?.map((e) => (e as Map).cast<String, dynamic>())
          .toList(),
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
      assignedDeliveryStaffId: map['assignedDeliveryStaffId'],
      collectedBy: map['collectedBy'],
      collectedAt: _parseDate(map['collectedAt']),
      receivedBy: map['receivedBy'],
      receivedAt: _parseDate(map['receivedAt']),
      cashCollectedBy: map['cashCollectedBy'],
      cashCollectedAt: _parseDate(map['cashCollectedAt']),
      cashCollectedAmount: (map['cashCollectedAmount'] as num?)?.toDouble(),
      cashReceivedBy: map['cashReceivedBy'],
      cashReceivedAt: _parseDate(map['cashReceivedAt']),
      rejectionReason: map['rejectionReason'],
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updatedAt']),
      completedAt: _parseDate(map['completedAt']),
      approvedAt: _parseDate(map['approvedAt']),
      readyForPickupAt: _parseDate(map['readyForPickupAt']),
      pickupDeadlineAt: _parseDate(map['pickupDeadlineAt']),
      deliveryRequestStatus: map['deliveryRequestStatus'],
      deliveryRequestSource: map['deliveryRequestSource'],
      deliveryRequestId: map['deliveryRequestId'],
      deliveryRequestedAt: _parseDate(map['deliveryRequestedAt']),
      deliveryDeadlineAt: _parseDate(map['deliveryDeadlineAt']),
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
      soapDeducted: map['soapDeducted'] ?? false,
      inventoryDeductedAt: _parseDate(map['inventoryDeductedAt']),
    );
  }

  bool get isWeightVerified => weightStatus == null || weightStatus == 'verified';

  String? get customerAddress =>
      deliveryAddress != null
          ? (deliveryAddress!.fullAddress.isNotEmpty
              ? deliveryAddress!.fullAddress
              : deliveryAddress!.street)
          : null;

  double get displayedEstimatedWeight => estimatedWeight ?? weight;

  /// Weight used for current laundry operations and staff display.
  /// The original declared/estimated weight remains available through
  /// [weight] and [displayedEstimatedWeight] for audit/history.
  double get operationalWeight {
    if (weightStatus == 'verified' &&
        actualWeight != null &&
        actualWeight!.isFinite &&
        actualWeight! > 0) {
      return actualWeight!;
    }
    return displayedEstimatedWeight;
  }

  bool get hasVerifiedActualWeight =>
      weightStatus == 'verified' &&
      actualWeight != null &&
      actualWeight!.isFinite &&
      actualWeight! > 0;

  /// Human-readable label for how the laundry reached the shop.
  String get collectionMethodLabel {
    return deliveryMethod == 'Pickup' ? 'Staff Pickup' : 'Customer Drop-off';
  }

  /// Human-readable label for the payment context.
  String get paymentMethodLabel {
    if (paymentMethod == 'GCash') return 'GCash';
    if (paymentMethod == 'Cash at Shop') return 'Cash at Shop';
    if (paymentMethod == 'Cash on Pickup') return 'Cash on Pickup';
    
    // Fallback logic for legacy or inconsistent data
    if (deliveryMethod == 'Pickup') {
      return 'Cash on Pickup';
    }
    return 'Cash at Shop';
  }

  /// Human-readable label for the payment status.
  String get paymentStatusDisplay {
    if (paymentStatus == 'Verified') return 'PAID';
    return paymentStatus;
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
