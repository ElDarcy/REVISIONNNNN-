import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/engagement_models.dart';

/// Customer-facing request gateway. It never writes discounts, balances, or
/// membership state; Cloud Functions own those authoritative transitions.
class EngagementCustomerService {
  EngagementCustomerService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  Stream<Map<String, dynamic>?> subscription(String customerId) => _db.collection('subscriptions').where('customerId', isEqualTo: customerId).orderBy('createdAt', descending: true).limit(1).snapshots().map((s) => s.docs.isEmpty ? null : {...s.docs.first.data(), 'id': s.docs.first.id});
  Stream<DocumentSnapshot<Map<String, dynamic>>> balance(String customerId) => _db.collection('loyalty_balances').doc(customerId).snapshots();
  Stream<QuerySnapshot<Map<String, dynamic>>> rewards() => _db.collection('loyalty_rewards').where('status', isEqualTo: 'Active').snapshots();
  Stream<QuerySnapshot<Map<String, dynamic>>> promotions() => _db.collection('promotions').where('status', isEqualTo: 'Active').snapshots();
  Future<String> requestPromo({required String customerId, required String code, String? orderId, double? laundrySubtotal}) async { final ref = _db.collection('promo_redemption_requests').doc(); await ref.set({'customerId': customerId, 'code': code.trim().toUpperCase(), 'orderId': orderId, 'laundrySubtotal': laundrySubtotal, 'createdAt': FieldValue.serverTimestamp()}); return ref.id; }
  Future<String> requestReward({required String customerId, required String rewardId}) async { final ref = _db.collection('loyalty_redemption_requests').doc(); await ref.set({'customerId': customerId, 'rewardId': rewardId, 'createdAt': FieldValue.serverTimestamp()}); return ref.id; }
}
