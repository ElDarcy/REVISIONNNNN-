class ReceiptModel {
  final String id;
  final String orderId;
  final String userId;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final List<Map<String, dynamic>> items;
  final double subtotal;
  final double deliveryFee;
  final double totalAmount;
  final double amountPaid;
  final double? change;
  final String paymentMethod;
  final String paymentStatus;
  final String? referenceNumber;
  final DateTime orderDate;
  final DateTime? completedDate;
  final String? barcode;
  final String? qrCode;
  final bool isPrinted;

  ReceiptModel({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    this.items = const [],
    this.subtotal = 0,
    this.deliveryFee = 0,
    this.totalAmount = 0,
    this.amountPaid = 0,
    this.change,
    this.paymentMethod = 'GCash',
    this.paymentStatus = 'Pending',
    this.referenceNumber,
    DateTime? orderDate,
    this.completedDate,
    this.barcode,
    this.qrCode,
    this.isPrinted = false,
  }) : orderDate = orderDate ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'orderId': orderId,
      'userId': userId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerAddress': customerAddress,
      'items': items,
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'totalAmount': totalAmount,
      'amountPaid': amountPaid,
      'change': change,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'referenceNumber': referenceNumber,
      'orderDate': orderDate.toIso8601String(),
      'completedDate': completedDate?.toIso8601String(),
      'barcode': barcode,
      'qrCode': qrCode,
      'isPrinted': isPrinted,
    };
  }

  factory ReceiptModel.fromMap(Map<String, dynamic> map, String id) {
    return ReceiptModel(
      id: id,
      orderId: map['orderId'] ?? '',
      userId: map['userId'] ?? '',
      customerName: map['customerName'] ?? '',
      customerPhone: map['customerPhone'] ?? '',
      customerAddress: map['customerAddress'] ?? '',
      items: List<Map<String, dynamic>>.from(map['items'] ?? []),
      subtotal: (map['subtotal'] ?? 0).toDouble(),
      deliveryFee: (map['deliveryFee'] ?? 0).toDouble(),
      totalAmount: (map['totalAmount'] ?? 0).toDouble(),
      amountPaid: (map['amountPaid'] ?? 0).toDouble(),
      change: (map['change']?.toDouble()),
      paymentMethod: map['paymentMethod'] ?? 'GCash',
      paymentStatus: map['paymentStatus'] ?? 'Pending',
      referenceNumber: map['referenceNumber'],
      orderDate: map['orderDate'] != null
          ? DateTime.parse(map['orderDate'])
          : DateTime.now(),
      completedDate: map['completedDate'] != null
          ? DateTime.parse(map['completedDate'])
          : null,
      barcode: map['barcode'],
      qrCode: map['qrCode'],
      isPrinted: map['isPrinted'] ?? false,
    );
  }
}
