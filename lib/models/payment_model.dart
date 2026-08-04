class PaymentModel {
  final String id;
  final String orderId;
  final String userId;
  final double amount;
  final String method;
  final String status;
  final String? referenceNumber;
  final String? receiptImageUrl;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final String? rejectionReason;
  final DateTime? approvedAt;
  final int? estimatedDuration;
  final DateTime? estimatedFinishTime;
  final DateTime createdAt;

  PaymentModel({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.amount,
    this.method = 'GCash',
    this.status = 'Pending Verification',
    this.referenceNumber,
    this.receiptImageUrl,
    this.verifiedBy,
    this.verifiedAt,
    this.rejectionReason,
    this.approvedAt,
    this.estimatedDuration,
    this.estimatedFinishTime,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'orderId': orderId,
      'userId': userId,
      'amount': amount,
      'method': method,
      'status': status,
      'referenceNumber': referenceNumber,
      'receiptImageUrl': receiptImageUrl,
      'verifiedBy': verifiedBy,
      'verifiedAt': verifiedAt?.toIso8601String(),
      'rejectionReason': rejectionReason,
      'approvedAt': approvedAt?.toIso8601String(),
      'estimatedDuration': estimatedDuration,
      'estimatedFinishTime': estimatedFinishTime?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory PaymentModel.fromMap(Map<String, dynamic> map, String id) {
    return PaymentModel(
      id: id,
      orderId: map['orderId'] ?? '',
      userId: map['userId'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      method: map['method'] ?? 'GCash',
      status: map['status'] ?? 'Pending Verification',
      referenceNumber: map['referenceNumber'],
      receiptImageUrl: map['receiptImageUrl'],
      verifiedBy: map['verifiedBy'],
      verifiedAt: map['verifiedAt'] != null
          ? DateTime.parse(map['verifiedAt'])
          : null,
      rejectionReason: map['rejectionReason'],
      approvedAt: map['approvedAt'] != null
          ? DateTime.parse(map['approvedAt'])
          : null,
      estimatedDuration: (map['estimatedDuration'] as num?)?.toInt(),
      estimatedFinishTime: map['estimatedFinishTime'] != null
          ? DateTime.parse(map['estimatedFinishTime'])
          : null,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }

  /// Creates a copy with updated fields
  PaymentModel copyWith({
    String? id,
    String? orderId,
    String? userId,
    double? amount,
    String? method,
    String? status,
    String? referenceNumber,
    String? receiptImageUrl,
    String? verifiedBy,
    DateTime? verifiedAt,
    String? rejectionReason,
    DateTime? approvedAt,
    int? estimatedDuration,
    DateTime? estimatedFinishTime,
    DateTime? createdAt,
  }) {
    return PaymentModel(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      userId: userId ?? this.userId,
      amount: amount ?? this.amount,
      method: method ?? this.method,
      status: status ?? this.status,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      receiptImageUrl: receiptImageUrl ?? this.receiptImageUrl,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      approvedAt: approvedAt ?? this.approvedAt,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      estimatedFinishTime: estimatedFinishTime ?? this.estimatedFinishTime,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
