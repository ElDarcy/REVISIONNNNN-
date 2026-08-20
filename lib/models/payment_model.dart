class PaymentModel {
  final String id;
  final String orderId;
  final String userId;
  final double amount;
  final String method;
  /// `laundry` is the original order payment; `delivery_fee` is a separate
  /// final-fulfilment payment for the same order.
  final String paymentType;
  final String status;
  final String? referenceNumber;
  /// Download URL for legacy receipts uploaded to Firebase Storage. New
  /// receipts are stored as Base64 in the `transaction_proofs` collection and
  /// referenced by [receiptProofId] instead.
  final String? receiptImageUrl;
  /// Document ID in `transaction_proofs` holding the Base64 receipt image
  /// (`proof_type: 'gcash_receipt'`). Null for legacy Storage receipts.
  final String? receiptProofId;
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
    this.paymentType = 'laundry',
    this.status = 'Pending Verification',
    this.referenceNumber,
    this.receiptImageUrl,
    this.receiptProofId,
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
      'paymentType': paymentType,
      'status': status,
      'referenceNumber': referenceNumber,
      'receiptImageUrl': receiptImageUrl,
      'receiptProofId': receiptProofId,
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
      paymentType: map['paymentType'] ?? 'laundry',
      status: map['status'] ?? 'Pending Verification',
      referenceNumber: map['referenceNumber'],
      receiptImageUrl: map['receiptImageUrl'],
      receiptProofId: map['receiptProofId'],
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
    String? paymentType,
    String? status,
    String? referenceNumber,
    String? receiptImageUrl,
    String? receiptProofId,
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
      paymentType: paymentType ?? this.paymentType,
      status: status ?? this.status,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      receiptImageUrl: receiptImageUrl ?? this.receiptImageUrl,
      receiptProofId: receiptProofId ?? this.receiptProofId,
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
