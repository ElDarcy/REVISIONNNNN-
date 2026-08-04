class TransactionModel {
  final String id;
  final String orderId;
  final String userId;
  final String type;
  final double amount;
  final String paymentMethod;
  final String status;
  final String? description;
  final DateTime createdAt;

  TransactionModel({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.type,
    required this.amount,
    this.paymentMethod = 'GCash',
    this.status = 'Completed',
    this.description,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'orderId': orderId,
      'userId': userId,
      'type': type,
      'amount': amount,
      'paymentMethod': paymentMethod,
      'status': status,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map, String id) {
    return TransactionModel(
      id: id,
      orderId: map['orderId'] ?? '',
      userId: map['userId'] ?? '',
      type: map['type'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      paymentMethod: map['paymentMethod'] ?? 'GCash',
      status: map['status'] ?? 'Completed',
      description: map['description'],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }
}
