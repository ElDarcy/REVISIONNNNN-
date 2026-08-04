class PrinterModel {
  final String id;
  final String name;
  final String type;
  final String? address;
  final String? port;
  final bool isDefault;
  final bool isConnected;

  PrinterModel({
    required this.id,
    required this.name,
    this.type = 'thermal',
    this.address,
    this.port,
    this.isDefault = false,
    this.isConnected = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'address': address,
      'port': port,
      'isDefault': isDefault,
      'isConnected': isConnected,
    };
  }

  factory PrinterModel.fromMap(Map<String, dynamic> map, String id) {
    return PrinterModel(
      id: id,
      name: map['name'] ?? '',
      type: map['type'] ?? 'thermal',
      address: map['address'],
      port: map['port'],
      isDefault: map['isDefault'] ?? false,
      isConnected: map['isConnected'] ?? false,
    );
  }
}
