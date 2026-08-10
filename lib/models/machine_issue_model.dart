import 'package:cloud_firestore/cloud_firestore.dart';

/// A machine issue reported by staff.
///
/// When a staff member reports an issue, the machine is moved to
/// 'under_inspection' (after any active load finishes) so an admin can decide
/// whether to return it to Available, put it into Maintenance, or set it to
/// Inactive.
class MachineIssueModel {
  final String issueId;
  final String machineId;
  final String issueCategory; // Mechanical | Electrical | Other
  final String description;
  final String reportedBy;
  final DateTime reportedAt;

  MachineIssueModel({
    required this.issueId,
    required this.machineId,
    required this.issueCategory,
    required this.description,
    required this.reportedBy,
    required this.reportedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'issueId': issueId,
      'machineId': machineId,
      'issueCategory': issueCategory,
      'description': description,
      'reportedBy': reportedBy,
      'reportedAt': Timestamp.fromDate(reportedAt),
    };
  }

  factory MachineIssueModel.fromMap(Map<String, dynamic> map, String id) {
    return MachineIssueModel(
      issueId: map['issueId'] ?? id,
      machineId: map['machineId'] ?? '',
      issueCategory: map['issueCategory'] ?? '',
      description: map['description'] ?? '',
      reportedBy: map['reportedBy'] ?? '',
      reportedAt: _parseTimestamp(map['reportedAt']) ?? DateTime.now(),
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
