class DeliveryModel {
  final String id;
  final String orderId;
  final String? staffId;
  final String? staffName;
  final String customerId;
  final String customerName;
  final String customerAddress;
  final double customerLatitude;
  final double customerLongitude;
  final double distanceKm;
  final String priority;
  final String status;
  final int queueOrder;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime createdAt;

  DeliveryModel({
    required this.id,
    required this.orderId,
    this.staffId,
    this.staffName,
    required this.customerId,
    required this.customerName,
    required this.customerAddress,
    required this.customerLatitude,
    required this.customerLongitude,
    this.distanceKm = 0,
    this.priority = 'Medium',
    this.status = 'Pending',
    this.queueOrder = 0,
    this.pickedUpAt,
    this.deliveredAt,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'orderId': orderId,
      'staffId': staffId,
      'staffName': staffName,
      'customerId': customerId,
      'customerName': customerName,
      'customerAddress': customerAddress,
      'customerLatitude': customerLatitude,
      'customerLongitude': customerLongitude,
      'distanceKm': distanceKm,
      'priority': priority,
      'status': status,
      'queueOrder': queueOrder,
      'pickedUpAt': pickedUpAt?.toIso8601String(),
      'deliveredAt': deliveredAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory DeliveryModel.fromMap(Map<String, dynamic> map, String id) {
    return DeliveryModel(
      id: id,
      orderId: map['orderId'] ?? '',
      staffId: map['staffId'],
      staffName: map['staffName'],
      customerId: map['customerId'] ?? '',
      customerName: map['customerName'] ?? '',
      customerAddress: map['customerAddress'] ?? '',
      customerLatitude: (map['customerLatitude'] ?? 0).toDouble(),
      customerLongitude: (map['customerLongitude'] ?? 0).toDouble(),
      distanceKm: (map['distanceKm'] ?? 0).toDouble(),
      priority: map['priority'] ?? 'Medium',
      status: map['status'] ?? 'Pending',
      queueOrder: map['queueOrder'] ?? 0,
      pickedUpAt: map['pickedUpAt'] != null
          ? DateTime.parse(map['pickedUpAt'])
          : null,
      deliveredAt: map['deliveredAt'] != null
          ? DateTime.parse(map['deliveredAt'])
          : null,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }
}
