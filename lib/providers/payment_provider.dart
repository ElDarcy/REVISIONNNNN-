import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/payment_model.dart';
import '../services/storage_service.dart';
import '../engines/service_time_estimator.dart';
import '../engines/order_status_flow_engine.dart';
import '../engines/order_load_engine.dart';
import '../models/order_model.dart';

class PaymentProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StorageService _storageService = StorageService();
  final Uuid _uuid = const Uuid();

  List<PaymentModel> _pendingPayments = [];
  bool _isLoading = false;
  String? _error;

  List<PaymentModel> get pendingPayments => _pendingPayments;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Stream<List<PaymentModel>> streamPendingPayments() {
    return _firestore
        .collection('payments')
        .where('status', isEqualTo: 'Pending Verification')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PaymentModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Stream<List<PaymentModel>> streamUserPayments(String userId) {
    return _firestore
        .collection('payments')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PaymentModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Stream payments that need verification (includes all statuses for admin)
  Stream<List<PaymentModel>> streamAllPayments() {
    return _firestore
        .collection('payments')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => PaymentModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<bool> processGCashPayment({
    required String orderId,
    required String userId,
    required double amount,
    required String referenceNumber,
    required String receiptImagePath,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final receiptUrl = await _storageService.uploadReceiptImage(
        receiptFile: File(receiptImagePath),
        userId: userId,
        orderId: orderId,
      );

      final paymentId = _uuid.v4();
      final payment = PaymentModel(
        id: paymentId,
        orderId: orderId,
        userId: userId,
        amount: amount,
        method: 'GCash',
        referenceNumber: referenceNumber,
        receiptImageUrl: receiptUrl,
      );

      await _firestore
          .collection('payments')
          .doc(paymentId)
          .set(payment.toMap());
      await _firestore.collection('orders').doc(orderId).update({
        'paymentStatus': 'Pending Verification',
        'status': 'Payment Pending Verification',
        'updatedAt': DateTime.now().toIso8601String(),
      });

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Payment processing failed.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Approve or reject a payment.
  /// When approved:
  ///   - paymentStatus => Verified
  ///   - order status => Washing
  ///   - approvedAt & estimatedFinishTime are saved (laundry timer starts)
  /// When rejected:
  ///   - paymentStatus => Rejected
  ///   - rejection reason is saved
  Future<bool> verifyPayment(
    String paymentId,
    String adminId, {
    required bool approved,
    String? rejectionReason,
  }) async {
    try {
      final now = DateTime.now();

      if (approved) {
        // Get the associated order
        final paymentDoc = await _firestore
            .collection('payments')
            .doc(paymentId)
            .get();
        final orderId = paymentDoc.data()?['orderId'] as String?;

        // Determine cycles from the order:
        // 1. explicit 'cycles' field (walk-in orders)
        // 2. items[].quantity (customer orders store cycles in item quantity)
        // 3. derive from weight (max 8kg per cycle)
        int cycles = 1;
        double weight = 0;
        if (orderId != null) {
          final orderDoc = await _firestore
              .collection('orders')
              .doc(orderId)
              .get();
          final orderData = orderDoc.data();
          if (orderData != null) {
            weight = (orderData['weight'] ?? 0).toDouble();
            cycles = (orderData['cycles'] as num?)?.toInt() ?? 0;

            if (cycles <= 0) {
              final items = orderData['items'] as List<dynamic>?;
              if (items != null && items.isNotEmpty) {
                final qty = (items.first['quantity'] as num?)?.toDouble() ?? 0;
                cycles = qty.round();
              }
            }
          }
        }

        // If no explicit cycles field, derive from weight (max 8kg per cycle)
        if (cycles <= 0) {
          cycles = ServiceTimeEstimator.getCycleCount(weight);
        }
        if (cycles <= 0) {
          cycles = 1;
        }

        // 38 MINS PER CYCLE
        final estimatedDuration = ServiceTimeEstimator.estimateMinutesForCycles(
          cycles,
        );

        // Update payment document (NOTE: estimatedFinishTime removed)
        await _firestore.collection('payments').doc(paymentId).update({
          'status': 'Verified',
          'verifiedBy': adminId,
          'verifiedAt': now.toIso8601String(),
          'approvedAt': now.toIso8601String(),
          'estimatedDuration': estimatedDuration,
        });

        // Update the associated order
        if (orderId != null) {
          final orderDoc = await _firestore.collection('orders').doc(orderId).get();
          final orderData = orderDoc.data();
          if (orderData != null) {
             final orderObj = OrderModel.fromMap(orderData, orderId);
             // 1. Create loads first
             await OrderLoadEngine.createLoadsForOrder(_firestore, orderObj);
             
             // 2. Update status second (triggers scheduler)
             await _firestore.collection('orders').doc(orderId).update({
               'paymentStatus': 'Verified',
               'status': OrderStatusFlowEngine.statusPaymentVerified,
               'approvedAt': now.toIso8601String(),
               'estimatedDuration': estimatedDuration,
               'updatedAt': now.toIso8601String(),
             });
          }
        }
      } else {
        // Reject
        await _firestore.collection('payments').doc(paymentId).update({
          'status': 'Rejected',
          'verifiedBy': adminId,
          'verifiedAt': now.toIso8601String(),
          'rejectionReason': rejectionReason ?? 'No reason provided',
        });

        final paymentDoc = await _firestore
            .collection('payments')
            .doc(paymentId)
            .get();
        final orderId = paymentDoc.data()?['orderId'] as String?;

        if (orderId != null) {
          await _firestore.collection('orders').doc(orderId).update({
            'paymentStatus': 'Rejected',
            'rejectionReason': rejectionReason ?? 'No reason provided',
            'updatedAt': now.toIso8601String(),
          });
        }
      }
      return true;
    } catch (e) {
      _error = 'Verification failed.';
      notifyListeners();
      return false;
    }
  }

  Future<List<PaymentModel>> loadPendingPayments() async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('status', isEqualTo: 'Pending Verification')
          .orderBy('createdAt', descending: true)
          .get();
      _pendingPayments = snapshot.docs
          .map((doc) => PaymentModel.fromMap(doc.data(), doc.id))
          .toList();
      notifyListeners();
      return _pendingPayments;
    } catch (e) {
      _error = 'Failed to load payments.';
      return [];
    }
  }

  /// Get a single payment by ID
  Future<PaymentModel?> getPaymentById(String paymentId) async {
    try {
      final doc = await _firestore.collection('payments').doc(paymentId).get();
      if (doc.exists) {
        return PaymentModel.fromMap(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
