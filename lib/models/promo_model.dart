class PromoModel {
  final String id;
  final String code;
  final String title;
  final String description;
  final double discountPercentage;
  final double? maxDiscountAmount;
  final double? minOrderAmount;
  final int? maxUses;
  final int currentUses;
  final DateTime validFrom;
  final DateTime validUntil;
  final bool isActive;
  final String? applicableServiceType;

  PromoModel({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    this.discountPercentage = 0,
    this.maxDiscountAmount,
    this.minOrderAmount,
    this.maxUses,
    this.currentUses = 0,
    required this.validFrom,
    required this.validUntil,
    this.isActive = true,
    this.applicableServiceType,
  });

  bool get isValid {
    final now = DateTime.now();
    return isActive &&
        now.isAfter(validFrom) &&
        now.isBefore(validUntil) &&
        (maxUses == null || currentUses < maxUses!);
  }

  double calculateDiscount(double orderTotal) {
    if (!isValid) return 0;
    if (minOrderAmount != null && orderTotal < minOrderAmount!) return 0;
    final discount = orderTotal * (discountPercentage / 100);
    if (maxDiscountAmount != null && discount > maxDiscountAmount!) {
      return maxDiscountAmount!;
    }
    return discount;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'title': title,
      'description': description,
      'discountPercentage': discountPercentage,
      'maxDiscountAmount': maxDiscountAmount,
      'minOrderAmount': minOrderAmount,
      'maxUses': maxUses,
      'currentUses': currentUses,
      'validFrom': validFrom.toIso8601String(),
      'validUntil': validUntil.toIso8601String(),
      'isActive': isActive,
      'applicableServiceType': applicableServiceType,
    };
  }

  factory PromoModel.fromMap(Map<String, dynamic> map, String id) {
    return PromoModel(
      id: id,
      code: map['code'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      discountPercentage: (map['discountPercentage'] ?? 0).toDouble(),
      maxDiscountAmount: (map['maxDiscountAmount']?.toDouble()),
      minOrderAmount: (map['minOrderAmount']?.toDouble()),
      maxUses: map['maxUses'],
      currentUses: map['currentUses'] ?? 0,
      validFrom: DateTime.parse(map['validFrom']),
      validUntil: DateTime.parse(map['validUntil']),
      isActive: map['isActive'] ?? true,
      applicableServiceType: map['applicableServiceType'],
    );
  }
}
