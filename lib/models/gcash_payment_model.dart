class GCashPaymentModel {
  final String id;
  final String paymentId;
  final String referenceNumber;
  final String receiptImageUrl;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final String status;

  GCashPaymentModel({
    required this.id,
    required this.paymentId,
    required this.referenceNumber,
    required this.receiptImageUrl,
    this.verifiedBy,
    this.verifiedAt,
    this.status = 'Pending Verification',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'paymentId': paymentId,
      'referenceNumber': referenceNumber,
      'receiptImageUrl': receiptImageUrl,
      'verifiedBy': verifiedBy,
      'verifiedAt': verifiedAt?.toIso8601String(),
      'status': status,
    };
  }

  factory GCashPaymentModel.fromMap(Map<String, dynamic> map, String id) {
    return GCashPaymentModel(
      id: id,
      paymentId: map['paymentId'] ?? '',
      referenceNumber: map['referenceNumber'] ?? '',
      receiptImageUrl: map['receiptImageUrl'] ?? '',
      verifiedBy: map['verifiedBy'],
      verifiedAt: map['verifiedAt'] != null
          ? DateTime.parse(map['verifiedAt'])
          : null,
      status: map['status'] ?? 'Pending Verification',
    );
  }
}
