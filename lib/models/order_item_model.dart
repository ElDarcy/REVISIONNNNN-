class OrderItemModel {
  final String serviceId;
  final String serviceName;
  final double price;
  final double quantity;
  final String unit;

  OrderItemModel({
    required this.serviceId,
    required this.serviceName,
    required this.price,
    this.quantity = 1,
    this.unit = 'kg',
  });

  double get subtotal => price * quantity;

  Map<String, dynamic> toMap() {
    return {
      'serviceId': serviceId,
      'serviceName': serviceName,
      'price': price,
      'quantity': quantity,
      'unit': unit,
      'subtotal': subtotal,
    };
  }

  factory OrderItemModel.fromMap(Map<String, dynamic> map) {
    return OrderItemModel(
      serviceId: map['serviceId'] ?? '',
      serviceName: map['serviceName'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      quantity: (map['quantity'] ?? 1).toDouble(),
      unit: map['unit'] ?? 'kg',
    );
  }
}
