import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';

class MachineModel {
  final String id; // e.g. wash_01, dry_01
  final String machineId;
  final int machineNumber; // 1..9
  final String type; // 'wash' | 'dry'
  final String status; // available | washing | drying | maintenance | ...
  final String? currentOrderId;
  final String? currentLoadId;
  final int usageCount;
  final DateTime? lastUsed;
  final DateTime? lastUsedAt;
  final DateTime createdAt;
  final List<Map<String, dynamic>> maintenanceHistory;

  MachineModel({
    required this.id,
    required this.machineId,
    required this.machineNumber,
    required this.type,
    this.status = AppConstants.machineAvailable,
    this.currentOrderId,
    this.currentLoadId,
    this.usageCount = 0,
    this.lastUsed,
    this.lastUsedAt,
    DateTime? createdAt,
    this.maintenanceHistory = const [],
  }) : createdAt = createdAt ?? DateTime.now();

  String get label =>
      type == AppConstants.machineWasher ? 'Wash Machine' : 'Dryer';

  String get displayName =>
      '${type == AppConstants.machineWasher ? 'Wash' : 'Dry'} $machineNumber';

  bool get isAvailable => status == AppConstants.machineAvailable;
  bool get isReserved => status == AppConstants.machineReserved;
  bool get isBusy => status == AppConstants.machineBusy;
  bool get isInactive => status == AppConstants.machineInactive;
  bool get isUnderInspection => status == AppConstants.machineUnderInspection;
  bool get isWashing => status == AppConstants.machineWashing;
  bool get isDrying => status == AppConstants.machineDrying;
  bool get isInUse =>
      status == AppConstants.machineReserved ||
      status == AppConstants.machineBusy ||
      status == AppConstants.machineWashing ||
      status == AppConstants.machineDrying;
  bool get isMaintenance => status == AppConstants.machineMaintenance;

  /// Whether this machine type matches the given service needs.
  bool matchesType(String machineType) => type == machineType;

  MachineModel copyWith({
    String? status,
    String? currentOrderId,
    String? currentLoadId,
    int? usageCount,
    DateTime? lastUsed,
    DateTime? lastUsedAt,
    List<Map<String, dynamic>>? maintenanceHistory,
  }) {
    return MachineModel(
      id: id,
      machineId: machineId,
      machineNumber: machineNumber,
      type: type,
      status: status ?? this.status,
      currentOrderId: currentOrderId ?? this.currentOrderId,
      currentLoadId: currentLoadId ?? this.currentLoadId,
      usageCount: usageCount ?? this.usageCount,
      lastUsed: lastUsed ?? this.lastUsed,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      createdAt: createdAt,
      maintenanceHistory: maintenanceHistory ?? this.maintenanceHistory,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'machineId': machineId,
      'machineNumber': machineNumber,
      'type': type,
      'status': status,
      'currentOrderId': currentOrderId,
      'currentLoadId': currentLoadId,
      'usageCount': usageCount,
      'lastUsed': lastUsed == null ? null : Timestamp.fromDate(lastUsed!),
      'lastUsedAt': lastUsedAt == null ? null : Timestamp.fromDate(lastUsedAt!),
      'maintenanceHistory': maintenanceHistory,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory MachineModel.fromMap(Map<String, dynamic> map, String id) {
    final rawStatus = map['status'] ?? AppConstants.machineAvailable;
    final historyRaw = map['maintenanceHistory'] as List<dynamic>? ?? [];
    final history = historyRaw
        .map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
        .toList();
    return MachineModel(
      id: id,
      machineId: map['machineId'] ?? id,
      machineNumber: (map['machineNumber'] ?? 0).toInt(),
      type: map['type'] ?? '',
      status: rawStatus.toString().toLowerCase() == 'available'
          ? AppConstants.machineAvailable
          : rawStatus.toString().toLowerCase(),
      currentOrderId: map['currentOrderId'],
      currentLoadId: map['currentLoadId'],
      usageCount: (map['usageCount'] ?? 0).toInt(),
      lastUsed: _parseTimestamp(map['lastUsed']),
      lastUsedAt: _parseTimestamp(map['lastUsedAt']),
      maintenanceHistory: history,
      createdAt: _parseTimestamp(map['createdAt']) ?? DateTime.now(),
    );
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
