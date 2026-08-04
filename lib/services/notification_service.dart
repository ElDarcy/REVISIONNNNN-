import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notification_model.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<NotificationModel>> getUserNotifications(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => NotificationModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<void> sendNotification({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
    String? orderId,
  }) async {
    final docRef = _firestore.collection('notifications').doc();
    final notification = NotificationModel(
      id: docRef.id,
      userId: userId,
      title: title,
      body: body,
      type: type,
      orderId: orderId,
    );
    await docRef.set(notification.toMap());
  }

  Future<void> sendOrderUpdateNotification({
    required String userId,
    required String orderId,
    required String status,
  }) async {
    await sendNotification(
      userId: userId,
      title: 'Order Update',
      body:
          'Your order #${orderId.substring(0, 6).toUpperCase()} is now: $status',
      type: 'order_update',
      orderId: orderId,
    );
  }

  Future<void> sendPaymentNotification({
    required String userId,
    required String orderId,
    required String status,
  }) async {
    String title = status == 'Approved'
        ? 'Payment Approved'
        : 'Payment Rejected';
    String body = status == 'Approved'
        ? 'Your payment for order has been approved. We will start processing your laundry.'
        : 'Your payment was rejected. Please check and resubmit.';

    await sendNotification(
      userId: userId,
      title: title,
      body: body,
      type: 'payment',
      orderId: orderId,
    );
  }

  Future<void> markAsRead(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).update({
      'isRead': true,
    });
  }

  Future<int> getUnreadCount(String userId) async {
    final snapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();
    return snapshot.docs.length;
  }

  Future<void> markAllAsRead(String userId) async {
    final snapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }
}
