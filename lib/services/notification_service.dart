import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/notification_model.dart';
import '../core/constants/app_colors.dart';

class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static final NotificationService instance = NotificationService._();
  NotificationService._();
  factory NotificationService() => instance;

  Future<void> initialize() async {
    // 1. Local Notifications Setup (for foreground display)
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // 2. Listen for Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showForegroundNotification(message);
    });
  }

  /// Request notification permission. Called after user login, not at startup.
  Future<void> requestPermission() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    const androidDetails = AndroidNotificationDetails(
      'laundry_cycles',
      'Laundry Cycles',
      importance: Importance.max,
      priority: Priority.high,
      color: AppColors.primary,
    );
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    if (message.notification != null) {
      await _localNotifications.show(
        0,
        message.notification!.title,
        message.notification!.body,
        notificationDetails,
      );
    }
  }

  Future<void> registerToken(String userId) async {
    final token = await _fcm.getToken();
    if (token == null) return;

    await _firestore
        .collection('users')
        .doc(userId)
        .collection('fcmTokens')
        .doc(token)
        .set({
      'token': token,
      'createdAt': FieldValue.serverTimestamp(),
      'lastUsed': FieldValue.serverTimestamp(),
    });
  }

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
    if (userId == 'broadcast_staff') {
      await sendStaffNotification(title: title, body: body, type: type, orderId: orderId);
      return;
    }
    
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

  Future<void> sendStaffNotification({
    required String title,
    required String body,
    String type = 'operational',
    String? orderId,
  }) async {
    final staffSnap = await _firestore.collection('users').where('role', isEqualTo: 'staff').get();
    final batch = _firestore.batch();
    
    for (final staffDoc in staffSnap.docs) {
      final docRef = _firestore.collection('notifications').doc();
      final notification = NotificationModel(
        id: docRef.id,
        userId: staffDoc.id,
        title: title,
        body: body,
        type: type,
        orderId: orderId,
      );
      batch.set(docRef, notification.toMap());
    }
    
    await batch.commit();
  }

  Future<void> sendOrderUpdateNotification({
    required String userId,
    required String orderId,
    required String status,
  }) async {
    await sendNotification(
      userId: userId,
      title: 'Transaction Update',
      body:
          'Your transaction #${orderId.substring(0, 6).toUpperCase()} is now: $status',
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
        ? 'Your payment has been approved. We will start processing your laundry.'
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
