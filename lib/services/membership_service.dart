import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

/// Subscription payments use the same `transaction_proofs` Base64 collection
/// as weight evidence.  A proof upload is never an activation: only an admin
/// verification changes a subscription from Pending to Active.
class MembershipService {
  MembershipService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  final Uuid _uuid = const Uuid();

  Future<String> createPendingSubscription({required String customerId, required String planId}) async {
    final settings = await _db.doc('system_settings/business_features').get();
    if (settings.data()?['membershipEnabled'] == false) throw StateError('Membership is currently unavailable.');
    final plan = await _db.collection('membership_plans').doc(planId).get();
    if (!plan.exists || plan.data()?['status'] != 'Active') throw StateError('Membership plan is unavailable.');
    final id = _uuid.v4();
    await _db.collection('subscriptions').doc(id).set({
      'customerId': customerId, 'planId': planId, 'status': 'Pending', 'paymentStatus': 'Pending',
      'startDate': null, 'expiryDate': null, 'createdAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Future<void> uploadPaymentProof({required String subscriptionId, required String customerId, required String imageBase64}) async {
    final settings = await _db.doc('system_settings/business_features').get();
    if (settings.data()?['membershipEnabled'] == false) throw StateError('Membership is currently unavailable.');
    if (imageBase64.isEmpty || imageBase64.length > 700 * 1024) throw ArgumentError('Invalid proof image.');
    final proofId = _uuid.v4(); final subRef = _db.collection('subscriptions').doc(subscriptionId);
    await _db.runTransaction((tx) async {
      final sub = await tx.get(subRef);
      if (!sub.exists || sub.data()?['customerId'] != customerId || sub.data()?['status'] != 'Pending') throw StateError('Subscription cannot accept a payment proof.');
      tx.set(_db.collection('transaction_proofs').doc(proofId), {'txn_id': subscriptionId, 'proof_type': 'membership_payment', 'image_base64': imageBase64, 'createdAt': FieldValue.serverTimestamp(), 'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 3)))});
      tx.update(subRef, {'paymentProofId': proofId, 'paymentStatus': 'Pending Verification', 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  /// Invoke only from the existing admin payment-verification surface; Firestore
  /// rules must require an administrator for this write.
  Future<void> verifyPayment({required String subscriptionId, required String adminId, required bool approved, String? rejectionReason}) async {
    final ref = _db.collection('subscriptions').doc(subscriptionId);
    await _db.runTransaction((tx) async {
      final sub = await tx.get(ref); if (!sub.exists || sub.data()?['paymentStatus'] != 'Pending Verification') throw StateError('Subscription is not pending verification.');
      if (!approved) { tx.update(ref, {'paymentStatus': 'Rejected', 'status': 'Rejected', 'rejectionReason': rejectionReason ?? 'Rejected by administrator', 'verifiedBy': adminId, 'verifiedAt': FieldValue.serverTimestamp()}); return; }
      final plan = await tx.get(_db.collection('membership_plans').doc(sub.data()!['planId'])); if (!plan.exists || plan.data()?['status'] != 'Active') throw StateError('Plan is unavailable.');
      final start = DateTime.now();
      tx.update(ref, {'status': 'Active', 'paymentStatus': 'Verified', 'startDate': Timestamp.fromDate(start), 'expiryDate': Timestamp.fromDate(DateTime(start.year, start.month + 1, start.day)), 'verifiedBy': adminId, 'verifiedAt': FieldValue.serverTimestamp()});
    });
  }
}
