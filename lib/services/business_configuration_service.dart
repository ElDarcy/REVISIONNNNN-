import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/engagement_models.dart';

class BusinessConfigurationService {
  BusinessConfigurationService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  static const featuresPath = 'system_settings/business_features';
  Stream<BusinessFeatures> watchFeatures() => _db.doc(featuresPath).snapshots().map((d) => BusinessFeatures.fromMap(d.data()));
  Stream<List<ServicePricing>> watchPricing() => _db.collection('service_pricing').snapshots().map((s) => s.docs.map((d) => ServicePricing.fromMap(d.id, d.data())).toList());
  Stream<List<MembershipPlan>> watchPlans() => _db.collection('membership_plans').snapshots().map((s) => s.docs.map((d) => MembershipPlan.fromMap(d.id, d.data())).toList());
  Stream<List<Promotion>> watchPromotions() => _db.collection('promotions').snapshots().map((s) => s.docs.map((d) => Promotion.fromMap(d.id, d.data())).toList());
  Future<void> setFeature(String field, bool enabled) => _db.doc(featuresPath).set({field: enabled, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  Future<void> savePricing(ServicePricing value) => _db.collection('service_pricing').doc(value.id).set(value.toMap(), SetOptions(merge: true));
  Future<void> savePlan(String id, Map<String, dynamic> value) => _db.collection('membership_plans').doc(id).set({...value, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  Future<void> savePromotion(String id, Map<String, dynamic> value) => _db.collection('promotions').doc(id).set({...value, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

  /// Idempotent seed for a new deployment. These are Firestore values, not
  /// customer-side calculation constants.
  Future<void> ensureInitialConfiguration() async {
    final batch = _db.batch();
    batch.set(_db.doc(featuresPath), const BusinessFeatures().toMap(), SetOptions(merge: true));
    for (final p in const [ServicePricing(id: 'wash_only', name: 'Wash Only', pricePerLoad: 70), ServicePricing(id: 'dry_only', name: 'Dry Only', pricePerLoad: 70), ServicePricing(id: 'wash_dry', name: 'Wash + Dry', pricePerLoad: 135)]) { batch.set(_db.collection('service_pricing').doc(p.id), p.toMap(), SetOptions(merge: true)); }
    batch.set(_db.collection('membership_plans').doc('premium'), {'name': 'Premium Laundry Membership', 'price': 99, 'billingPeriod': 'monthly', 'discountPercent': 5, 'prioritySchedulingEnabled': true, 'loyaltyMultiplier': 1.5, 'status': 'Active', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    batch.set(_db.doc('loyalty_settings/default'), {'spendAmount': 100, 'pointsAwarded': 10, 'status': 'Active', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    for (final reward in const [{'id': 'discount_50', 'name': '₱50 discount', 'requiredPoints': 100, 'type': 'fixed_discount', 'value': 50}, {'id': 'discount_150', 'name': '₱150 discount', 'requiredPoints': 250, 'type': 'fixed_discount', 'value': 150}, {'id': 'free_wash', 'name': 'Free Wash', 'requiredPoints': 500, 'type': 'free_service', 'value': 0}]) { batch.set(_db.collection('loyalty_rewards').doc(reward['id']! as String), {...reward, 'status': 'Active', 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true)); }
    await batch.commit();
  }
}
