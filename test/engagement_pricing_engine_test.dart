import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_app/engines/engagement_pricing_engine.dart';
import 'package:laundry_app/models/engagement_models.dart';

void main() {
  const washDry = ServicePricing(id: 'wash_dry', name: 'Wash + Dry', pricePerLoad: 135);
  test('uses existing ceil actual-weight load rule and configured price', () {
    final result = EngagementPricingEngine.calculate(actualWeight: 9.82, pricing: washDry, deliveryFee: 50);
    expect(result.loadCount, 2);
    expect(result.laundrySubtotal, 270);
    expect(result.total, 320);
  });
  test('uses the better eligible discount rather than stacking', () {
    const member = MembershipPlan(id: 'premium', name: 'Premium', price: 99, discountPercent: 5, loyaltyMultiplier: 1.5, prioritySchedulingEnabled: true);
    const promo = Promotion(id: 'welcome', code: 'WELCOME10', type: 'percentage', value: 10, maximumDiscount: 50);
    final result = EngagementPricingEngine.calculate(actualWeight: 32, pricing: washDry, deliveryFee: 0, membership: member, promo: promo);
    expect(result.laundrySubtotal, 540);
    expect(result.membershipDiscount, 0);
    expect(result.promoDiscount, 50);
  });
  test('applies membership only when the plan and subscription are active', () {
    const member = MembershipPlan(id: 'premium', name: 'Premium', price: 99, discountPercent: 5, loyaltyMultiplier: 1.5, prioritySchedulingEnabled: true);
    final result = EngagementPricingEngine.calculate(actualWeight: 8, pricing: washDry, deliveryFee: 50, membership: member, membershipIsActive: false);
    expect(result.membershipDiscount, 0);
    expect(result.total, 185);
  });
  test('rejects inactive, member-only, and expired promos', () {
    const memberOnly = Promotion(id: 'member', code: 'MEMBER', type: 'fixed', value: 20, memberOnly: true);
    final expired = Promotion(id: 'expired', code: 'OLD', type: 'percentage', value: 10, endDate: DateTime(2025));
    final memberOnlyResult = EngagementPricingEngine.calculate(actualWeight: 8, pricing: washDry, deliveryFee: 0, promo: memberOnly);
    final expiredResult = EngagementPricingEngine.calculate(actualWeight: 8, pricing: washDry, deliveryFee: 0, promo: expired, now: DateTime(2026));
    expect(memberOnlyResult.promoDiscount, 0);
    expect(expiredResult.promoDiscount, 0);
  });
  test('never discounts delivery fees or exceeds the laundry subtotal', () {
    const promo = Promotion(id: 'big', code: 'BIG', type: 'fixed', value: 500);
    final result = EngagementPricingEngine.calculate(actualWeight: 8, pricing: washDry, deliveryFee: 50, promo: promo);
    expect(result.promoDiscount, 135);
    expect(result.total, 50);
  });
  test('stacks only when explicitly allowed', () {
    const member = MembershipPlan(id: 'premium', name: 'Premium', price: 99, discountPercent: 5, loyaltyMultiplier: 1.5, prioritySchedulingEnabled: true);
    const promo = Promotion(id: 'promo', code: 'PROMO', type: 'fixed', value: 20);
    final result = EngagementPricingEngine.calculate(actualWeight: 8, pricing: washDry, deliveryFee: 50, membership: member, promo: promo, allowDiscountStacking: true);
    expect(result.membershipDiscount, 6.75);
    expect(result.promoDiscount, 20);
    expect(result.total, 158.25);
  });
}
