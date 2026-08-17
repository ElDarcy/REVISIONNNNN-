import 'package:cloud_firestore/cloud_firestore.dart';

/// Values in this document only enable optional customer features.  Core
/// payment, verified-weight, scheduling, machine, and delivery rules are not
/// configurable here.
class BusinessFeatures {
  final bool realTimeTrackingEnabled;
  final bool membershipEnabled;
  final bool promotionsEnabled;
  final bool loyaltyEnabled;
  final bool loyaltyRedemptionEnabled;
  final bool prioritySchedulingEnabled;

  const BusinessFeatures({
    this.realTimeTrackingEnabled = true,
    this.membershipEnabled = true,
    this.promotionsEnabled = true,
    this.loyaltyEnabled = true,
    this.loyaltyRedemptionEnabled = true,
    this.prioritySchedulingEnabled = true,
  });

  factory BusinessFeatures.fromMap(Map<String, dynamic>? map) => BusinessFeatures(
        realTimeTrackingEnabled: map?['realTimeTrackingEnabled'] ?? true,
        membershipEnabled: map?['membershipEnabled'] ?? true,
        promotionsEnabled: map?['promotionsEnabled'] ?? true,
        loyaltyEnabled: map?['loyaltyEnabled'] ?? true,
        loyaltyRedemptionEnabled: map?['loyaltyRedemptionEnabled'] ?? true,
        prioritySchedulingEnabled: map?['prioritySchedulingEnabled'] ?? true,
      );

  Map<String, dynamic> toMap() => {
        'realTimeTrackingEnabled': realTimeTrackingEnabled,
        'membershipEnabled': membershipEnabled,
        'promotionsEnabled': promotionsEnabled,
        'loyaltyEnabled': loyaltyEnabled,
        'loyaltyRedemptionEnabled': loyaltyRedemptionEnabled,
        'prioritySchedulingEnabled': prioritySchedulingEnabled,
      };
}

class ServicePricing {
  final String id;
  final String name;
  final double pricePerLoad;
  final double includedWeightKg;
  final String status;
  const ServicePricing({required this.id, required this.name, required this.pricePerLoad, this.includedWeightKg = 8, this.status = 'Active'});
  factory ServicePricing.fromMap(String id, Map<String, dynamic> map) => ServicePricing(
    id: id, name: map['name'] ?? id, pricePerLoad: (map['pricePerLoad'] as num?)?.toDouble() ?? 0,
    includedWeightKg: (map['includedWeightKg'] as num?)?.toDouble() ?? 8, status: map['status'] ?? 'Active');
  Map<String, dynamic> toMap() => {'name': name, 'pricePerLoad': pricePerLoad, 'includedWeightKg': includedWeightKg, 'status': status, 'updatedAt': FieldValue.serverTimestamp()};
}

class MembershipPlan {
  final String id; final String name; final double price; final double discountPercent;
  final double loyaltyMultiplier; final bool prioritySchedulingEnabled; final String status;
  const MembershipPlan({required this.id, required this.name, required this.price, required this.discountPercent, required this.loyaltyMultiplier, required this.prioritySchedulingEnabled, this.status = 'Active'});
  factory MembershipPlan.fromMap(String id, Map<String, dynamic> m) => MembershipPlan(id: id, name: m['name'] ?? id, price: (m['price'] as num?)?.toDouble() ?? 0, discountPercent: (m['discountPercent'] as num?)?.toDouble() ?? 0, loyaltyMultiplier: (m['loyaltyMultiplier'] as num?)?.toDouble() ?? 1, prioritySchedulingEnabled: m['prioritySchedulingEnabled'] ?? false, status: m['status'] ?? 'Inactive');
}

class Promotion {
  final String id; final String code; final String type; final double value; final double minimumOrderAmount; final double? maximumDiscount; final bool memberOnly; final int? usageLimit; final int? customerUsageLimit; final DateTime? startDate; final DateTime? endDate; final String status;
  const Promotion({required this.id, required this.code, required this.type, required this.value, this.minimumOrderAmount = 0, this.maximumDiscount, this.memberOnly = false, this.usageLimit, this.customerUsageLimit, this.startDate, this.endDate, this.status = 'Active'});
  factory Promotion.fromMap(String id, Map<String, dynamic> m) => Promotion(id: id, code: m['code'] ?? '', type: m['type'] ?? 'percentage', value: (m['value'] as num?)?.toDouble() ?? 0, minimumOrderAmount: (m['minimumOrderAmount'] as num?)?.toDouble() ?? 0, maximumDiscount: (m['maximumDiscount'] as num?)?.toDouble(), memberOnly: m['memberOnly'] ?? false, usageLimit: (m['usageLimit'] as num?)?.toInt(), customerUsageLimit: (m['customerUsageLimit'] as num?)?.toInt(), startDate: _date(m['startDate']), endDate: _date(m['endDate']), status: m['status'] ?? 'Inactive');
  static DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : v is DateTime ? v : v is String ? DateTime.tryParse(v) : null;

  bool isEligibleFor({
    required double laundrySubtotal,
    required bool hasActiveMembership,
    DateTime? now,
  }) {
    final instant = now ?? DateTime.now();
    return status == 'Active' &&
        (type == 'fixed' || type == 'percentage') &&
        value.isFinite &&
        value > 0 &&
        laundrySubtotal.isFinite &&
        laundrySubtotal >= minimumOrderAmount &&
        (!memberOnly || hasActiveMembership) &&
        (startDate == null || !instant.isBefore(startDate!)) &&
        (endDate == null || !instant.isAfter(endDate!));
  }
}

class PricingBreakdown {
  final int loadCount; final double laundrySubtotal; final double membershipDiscount; final double promoDiscount; final double deliveryFee;
  const PricingBreakdown({required this.loadCount, required this.laundrySubtotal, this.membershipDiscount = 0, this.promoDiscount = 0, this.deliveryFee = 0});
  double get total => laundrySubtotal - membershipDiscount - promoDiscount + deliveryFee;
  Map<String, dynamic> toMap() => {'loadCount': loadCount, 'laundrySubtotal': laundrySubtotal, 'membershipDiscount': membershipDiscount, 'promoDiscount': promoDiscount, 'deliveryFee': deliveryFee, 'total': total};
}
