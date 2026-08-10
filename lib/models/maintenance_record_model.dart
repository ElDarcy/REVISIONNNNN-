import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';

/// A maintenance record for a machine (admin-managed).
///
/// Tracks the full lifecycle of machine downtime: who reported it, when it
/// started, the expected/actual completion, the current status
/// (Pending / In Progress / Completed), the reason, and notes.
class MaintenanceRecordModel {
  final String maintenanceId;
  final String machineId;
  final String machineType; // 'wash' | 'dry'
  final String reason;
  final String reportedBy;
  final DateTime startedAt;
  final DateTime? expectedCompletionDate;
  final DateTime? completedAt;
  final String status; // Pending | In Progress | Completed
  final String notes;

  MaintenanceRecordModel({
    required this.maintenanceId,
    required this.machineId,
    required this.machineType,
    required this.reason,
    required this.reportedBy,
    required this.startedAt,
    this.expectedCompletionDate,
    this.completedAt,
    this.status = AppConstants.maintenancePending,
    this.notes = '',
  });

  bool get isCompleted => status == AppConstants.maintenanceCompleted;

  Map<String, dynamic> toMap() {
    return {
      'maintenanceId': maintenanceId,
      'machineId': machineId,
      'machineType': machineType,
      'reason': reason,
      'reportedBy': reportedBy,
      'startedAt': Timestamp.fromDate(startedAt),
      'expectedCompletionDate': expectedCompletionDate == null
          ? null
          : Timestamp.fromDate(expectedCompletionDate!),
      'completedAt': completedAt == null
          ? null
          : Timestamp.fromDate(completedAt!),
      'status': status,
      'notes': notes,
    };
  }

  factory MaintenanceRecordModel.fromMap(Map<String, dynamic> map, String id) {
    return MaintenanceRecordModel(
      maintenanceId: map['maintenanceId'] ?? id,
      machineId: map['machineId'] ?? '',
      machineType: map['machineType'] ?? '',
      reason: map['reason'] ?? '',
      reportedBy: map['reportedBy'] ?? '',
      startedAt: _parseTimestamp(map['startedAt']) ?? DateTime.now(),
      expectedCompletionDate: _parseTimestamp(map['expectedCompletionDate']),
      completedAt: _parseTimestamp(map['completedAt']),
      status: map['status'] ?? AppConstants.maintenancePending,
      notes: map['notes'] ?? '',
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
