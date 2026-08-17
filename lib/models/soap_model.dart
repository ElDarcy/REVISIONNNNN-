class SoapModel {
  final String id;
  final String name;
  final String brand;
  final String description;
  final double price;
  final String unit;
  final String stockStatus;
  final int stockQuantity;
  final String category;
  final bool isActive;
  final String? imageUrl;
  final String colorHex;
  final int order;
  final DateTime createdAt;

  SoapModel({
    required this.id,
    required this.name,
    this.brand = '',
    this.description = '',
    this.price = 0,
    this.unit = 'sachet',
    this.stockStatus = 'In Stock',
    this.stockQuantity = 0,
    this.category = 'Detergent',
    this.isActive = true,
    this.imageUrl,
    this.colorHex = '#1565C0',
    this.order = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isInStock => stockStatus == 'In Stock' && stockQuantity > 0;

  static const int lowStockThreshold = 10;

  bool get isLowStock => stockQuantity > 0 && stockQuantity <= lowStockThreshold;

  bool get isOutOfStock => stockQuantity <= 0;

  String get inventoryStatus {
    if (isOutOfStock) return 'Out of Stock';
    if (isLowStock) return 'Low Stock';
    return 'Normal';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'brand': brand,
      'description': description,
      'price': price,
      'unit': unit,
      'stockStatus': stockStatus,
      'stockQuantity': stockQuantity,
      'category': category,
      'isActive': isActive,
      'imageUrl': imageUrl,
      'colorHex': colorHex,
      'order': order,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory SoapModel.fromMap(Map<String, dynamic> map, String id) {
    return SoapModel(
      id: id,
      name: map['name'] ?? '',
      brand: map['brand'] ?? '',
      description: map['description'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      unit: map['unit'] ?? 'sachet',
      stockStatus: map['stockStatus'] ?? 'In Stock',
      stockQuantity: map['stockQuantity'] ?? 0,
      category: map['category'] ?? 'Detergent',
      isActive: map['isActive'] ?? true,
      imageUrl: map['imageUrl'],
      colorHex: map['colorHex'] ?? '#1565C0',
      order: map['order'] ?? 0,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => toMap();

  SoapModel copyWith({
    String? id,
    String? name,
    String? brand,
    String? description,
    double? price,
    String? unit,
    String? stockStatus,
    int? stockQuantity,
    String? category,
    bool? isActive,
    String? imageUrl,
    String? colorHex,
    int? order,
    DateTime? createdAt,
  }) {
    return SoapModel(
      id: id ?? this.id,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      description: description ?? this.description,
      price: price ?? this.price,
      unit: unit ?? this.unit,
      stockStatus: stockStatus ?? this.stockStatus,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      category: category ?? this.category,
      isActive: isActive ?? this.isActive,
      imageUrl: imageUrl ?? this.imageUrl,
      colorHex: colorHex ?? this.colorHex,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
