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
///
/// Machine operations are controlled through this record. A load stores BOTH
/// the assigned washer and dryer separately (for 'Wash and Dry' service) as
/// well as per-cycle timers for the wash and dry phases:
///
///   {
///     loadId,
///     orderId,
///     loadNumber,
///     weight,
///     serviceType,
///     washerId,
///     dryerId,
///     status,
///     washCycleStart,
///     washEstimatedFinish,
///     dryCycleStart,
///     dryEstimatedFinish
///   }
class OrderLoadModel {
  final String id; // loadId
  final String orderId;
  final int loadNumber; // 1-based load number within the order
  final double weight; // kg for this load (max 8kg, last may be less)
  final String serviceType; // 'Wash Only' | 'Dry Only' | 'Wash and Dry'

  // Assigned machines (independent of one another).
  final String? washerId; // e.g. wash_01 (null until assigned)
  final String? dryerId; // e.g. dry_01 (null until assigned)

  final LaundryStatus status;

  // Wash-cycle timing (only set when the wash actually starts).
  final DateTime? washCycleStart;
  final DateTime? washEstimatedFinish;

  // Dry-cycle timing (only set when the dry actually starts).
  final DateTime? dryCycleStart;
  final DateTime? dryEstimatedFinish;

  final DateTime createdAt;
  final DateTime? updatedAt;

  OrderLoadModel({
    required this.id,
    required this.orderId,
    required this.loadNumber,
    required this.weight,
    required this.serviceType,
    this.washerId,
    this.dryerId,
    this.status = LaundryStatus.paymentVerified,
    this.washCycleStart,
    this.washEstimatedFinish,
    this.dryCycleStart,
    this.dryEstimatedFinish,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get loadLabel => 'Load $loadNumber';

  /// The washer machine id assigned to this load (null until assigned).
  String? get assignedWasherId => washerId;

  /// The dryer machine id assigned to this load (null until assigned).
  String? get assignedDryerId => dryerId;

  /// The machine currently operating this load (whichever step is active).
  String? get currentMachineId {
    switch (status) {
      case LaundryStatus.machineAssigned:
      case LaundryStatus.washing:
        return washerId;
      case LaundryStatus.dryerAssigned:
      case LaundryStatus.drying:
        return dryerId;
      default:
        return null;
    }
  }

  OrderLoadModel copyWith({
    String? washerId,
    String? dryerId,
    LaundryStatus? status,
    DateTime? washCycleStart,
    DateTime? washEstimatedFinish,
    DateTime? dryCycleStart,
    DateTime? dryEstimatedFinish,
    DateTime? updatedAt,
    bool clearWasher = false,
    bool clearDryer = false,
  }) {
    return OrderLoadModel(
      id: id,
      orderId: orderId,
      loadNumber: loadNumber,
      weight: weight,
      serviceType: serviceType,
      washerId: clearWasher ? null : (washerId ?? this.washerId),
      dryerId: clearDryer ? null : (dryerId ?? this.dryerId),
      status: status ?? this.status,
      washCycleStart: washCycleStart ?? this.washCycleStart,
      washEstimatedFinish: washEstimatedFinish ?? this.washEstimatedFinish,
      dryCycleStart: dryCycleStart ?? this.dryCycleStart,
      dryEstimatedFinish: dryEstimatedFinish ?? this.dryEstimatedFinish,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'loadId': id,
      'orderId': orderId,
      'loadNumber': loadNumber,
      'weight': weight,
      'serviceType': serviceType,
      'washerId': washerId,
      'dryerId': dryerId,
      'status': status.value,
      'washCycleStart': washCycleStart?.toIso8601String(),
      'washEstimatedFinish': washEstimatedFinish?.toIso8601String(),
      'dryCycleStart': dryCycleStart?.toIso8601String(),
      'dryEstimatedFinish': dryEstimatedFinish?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      // Backward-compat mirrors (old screens/analytics may read these).
      'machineId': washerId ?? dryerId,
      'machineType': washerId != null
          ? 'wash'
          : (dryerId != null ? 'dry' : null),
      'machineNumber': _machineNumberFromId(washerId ?? dryerId),
      'cycleStart': washCycleStart ?? dryCycleStart,
      'estimatedFinish': washEstimatedFinish ?? dryEstimatedFinish,
    };
  }

  factory OrderLoadModel.fromMap(Map<String, dynamic> map, String id) {
    // Backward compatibility: old records used a single `machineId` with a
    // `machineType`. New records store `washerId`/`dryerId` separately.
    final oldMachineId = map['machineId'] ?? map['assignedMachineId'];
    final oldMachineType = map['machineType'] ?? map['assignedMachineType'];
    final String? washerId =
        map['washerId'] ?? (oldMachineType == 'wash' ? oldMachineId : null);
    final String? dryerId =
        map['dryerId'] ?? (oldMachineType == 'dry' ? oldMachineId : null);

    return OrderLoadModel(
      id: id,
      orderId: map['orderId'] ?? '',
      loadNumber: (map['loadNumber'] ?? 1).toInt(),
      weight: (map['weight'] ?? 0).toDouble(),
      serviceType: map['serviceType'] ?? 'Wash and Dry',
      washerId: washerId,
      dryerId: dryerId,
      status: LaundryStatus.fromString(map['status'] ?? 'Payment Verified'),
      washCycleStart:
          _parseDate(map['washCycleStart']) ?? _parseDate(map['cycleStart']),
      washEstimatedFinish:
          _parseDate(map['washEstimatedFinish']) ??
          _parseDate(map['estimatedFinish']),
      dryCycleStart: _parseDate(map['dryCycleStart']),
      dryEstimatedFinish: _parseDate(map['dryEstimatedFinish']),
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  static int? _machineNumberFromId(String? machineId) {
    if (machineId == null) return null;
    final match = RegExp(r'(\d+)').firstMatch(machineId);
    return match != null ? int.tryParse(match.group(1)!) : null;
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
