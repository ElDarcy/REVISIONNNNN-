class ServiceModel {
  final String id;
  final String name;
  final String description;
  final double pricePerKg;
  final double pricePerItem;
  final String type;
  final int estimatedMinutes;
  final double maxKgPerCycle;
  final bool isActive;
  final String? imageUrl;
  final int order;

  ServiceModel({
    required this.id,
    required this.name,
    required this.description,
    this.pricePerKg = 0,
    this.pricePerItem = 0,
    required this.type,
    this.estimatedMinutes = 120,
    this.maxKgPerCycle = 8.0,
    this.isActive = true,
    this.imageUrl,
    this.order = 0,
  });

  /// Returns the number of cycles needed based on weight
  int getCycleCount(double weight) {
    if (weight <= 0) return 0;
    return (weight / maxKgPerCycle).ceil();
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'pricePerKg': pricePerKg,
      'pricePerItem': pricePerItem,
      'type': type,
      'estimatedMinutes': estimatedMinutes,
      'maxKgPerCycle': maxKgPerCycle,
      'isActive': isActive,
      'imageUrl': imageUrl,
      'order': order,
    };
  }

  factory ServiceModel.fromMap(Map<String, dynamic> map, String id) {
    return ServiceModel(
      id: id,
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      pricePerKg: (map['pricePerKg'] ?? 0).toDouble(),
      pricePerItem: (map['pricePerItem'] ?? 0).toDouble(),
      type: map['type'] ?? '',
      estimatedMinutes: map['estimatedMinutes'] ?? 120,
      maxKgPerCycle: (map['maxKgPerCycle'] ?? 8.0).toDouble(),
      isActive: map['isActive'] ?? true,
      imageUrl: map['imageUrl'],
      order: map['order'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() => toMap();
}
