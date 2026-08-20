import '../models/engagement_models.dart';
import 'order_load_engine.dart';

/// Production pricing helper. It deliberately delegates load counting to the
/// existing OrderLoadEngine; discounts never alter actual-weight load rules.
class EngagementPricingEngine {
  static PricingBreakdown calculate({
    required double actualWeight,
    required ServicePricing pricing,
    required double deliveryFee,
    double soapTotal = 0,
    MembershipPlan? membership,
    Promotion? promo,
    bool membershipIsActive = true,
    bool allowDiscountStacking = false,
    DateTime? now,
  }) {
    final loads = OrderLoadEngine.computeNumberOfLoads(actualWeight);
    final double laundrySubtotal = loads * pricing.pricePerLoad + soapTotal;
    final hasActiveMembership = membershipIsActive && membership?.status == 'Active';
    final double memberDiscount = !hasActiveMembership
        ? 0
        : laundrySubtotal * membership!.discountPercent.clamp(0, 100) / 100;
    final double promoDiscount = promo == null ||
            !promo.isEligibleFor(
              laundrySubtotal: laundrySubtotal,
              hasActiveMembership: hasActiveMembership,
              now: now,
            )
        ? 0
        : _promoDiscount(promo, laundrySubtotal);
    final usePromo = promoDiscount > 0 &&
        (allowDiscountStacking || promoDiscount > memberDiscount);
    // One discount only unless the explicit feature rule permits stacking.
    return PricingBreakdown(
      loadCount: loads,
      laundrySubtotal: laundrySubtotal,
      membershipDiscount: allowDiscountStacking || !usePromo ? memberDiscount : 0,
      promoDiscount: usePromo ? promoDiscount : 0,
      deliveryFee: deliveryFee,
    );
  }

  static double _promoDiscount(Promotion p, double subtotal) {
    if (!subtotal.isFinite || subtotal <= 0) return 0;
    final raw = p.type == 'fixed' ? p.value : subtotal * p.value / 100;
    final cap = p.maximumDiscount == null
        ? subtotal
        : p.maximumDiscount!.clamp(0, subtotal).toDouble();
    return raw.clamp(0, cap).toDouble();
  }
}
