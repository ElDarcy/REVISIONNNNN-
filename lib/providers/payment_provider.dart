import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/payment_model.dart';
import '../engines/service_time_estimator.dart';
import '../engines/financial_settlement_engine.dart';
import '../engines/order_status_flow_engine.dart';
import '../engines/order_scheduling_gate.dart';

class PaymentProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  List<PaymentModel> _pendingPayments = [];
  bool _isLoading = false;
  String? _error;

  List<PaymentModel> get pendingPayments => _pendingPayments;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Stream<List<PaymentModel>> streamPendingPayments() {
    // Sorted client-side: combining `where('status')` with `orderBy('createdAt')`
    // requires a composite Firestore index, and a missing index makes the
    // stream error intermittently (cards appear then vanish). Ordering in
    // memory keeps the pending list stable with no index dependency.
    return _firestore
        .collection('payments')
        .where('status', isEqualTo: 'Pending Verification')
        .snapshots()
        .map(
          (snapshot) {
            final payments = snapshot.docs
                .map((doc) => PaymentModel.fromMap(doc.data(), doc.id))
                .toList();
            payments.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return payments;
          },
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
    String paymentType = 'laundry',
  }) async {
    try {
      final bytes = await File(receiptImagePath).readAsBytes();
      return await processGCashPaymentFromBytes(
        orderId: orderId,
        userId: userId,
        amount: amount,
        referenceNumber: referenceNumber,
        receiptBytes: bytes,
        paymentType: paymentType,
      );
    } catch (e) {
      _error = 'Payment processing failed.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> processGCashPaymentFromBytes({
    required String orderId,
    required String userId,
    required double amount,
    required String referenceNumber,
    required List<int> receiptBytes,
    String paymentType = 'laundry',
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Base64 is about 4/3 the final JPEG size. Keep the proof document
      // comfortably below Firestore's 1 MiB document limit.
      const maxProofBase64Bytes = 700 * 1024;
      final proofBase64 = base64Encode(receiptBytes);
      if (proofBase64.length > maxProofBase64Bytes) {
        _error = 'Receipt screenshot is too large. Please pick a smaller photo.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final now = DateTime.now();
      final proofId = _uuid.v4();
      final paymentId = _uuid.v4();
      final payment = PaymentModel(
        id: paymentId,
        orderId: orderId,
        userId: userId,
        amount: amount,
        method: 'GCash',
        paymentType: paymentType,
        referenceNumber: referenceNumber,
        receiptProofId: proofId,
      );

      // Write the receipt Base64 straight into Firestore (no Firebase Storage
      // round-trip) so the submit completes immediately instead of getting
      // stuck on the upload. Proofs live in `transaction_proofs`, the same
      // collection used for weight and membership proofs.
      final proofRef =
          _firestore.collection('transaction_proofs').doc(proofId);

      final batch = _firestore.batch();
      batch.set(
        proofRef,
        {
          'txn_id': orderId,
          'proof_type': 'gcash_receipt',
          'image_base64': proofBase64,
          'submitted_by': userId,
          'createdAt': now.toIso8601String(),
        },
      );
      batch.set(_firestore.collection('payments').doc(paymentId), payment.toMap());
      if (paymentType == 'laundry') {
        batch.update(_firestore.collection('orders').doc(orderId), {
          'paymentStatus': 'Pending Verification',
          'status': 'Payment Pending Verification',
          'updatedAt': now.toIso8601String(),
        });
      } else {
        batch.update(_firestore.collection('orders').doc(orderId), {
          'deliveryFeePaymentStatus': 'Pending Verification',
          'updatedAt': now.toIso8601String(),
        });
      }
      await batch.commit();

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
        final paymentData = paymentDoc.data();
        final orderId = paymentData?['orderId'] as String?;
        final paymentAmount = (paymentData?['amount'] as num?)?.toDouble() ?? 0;

        final paymentType = paymentData?['paymentType'] as String? ?? 'laundry';
        if (orderId == null) throw StateError('Payment has no order.');

        if (paymentType != 'laundry') {
          await _firestore.collection('payments').doc(paymentId).update({
            'status': 'Verified',
            'verifiedBy': adminId,
            'verifiedAt': now.toIso8601String(),
          });
          await _firestore.collection('orders').doc(orderId).update({
            'deliveryFeePaymentStatus': 'Verified',
            'updatedAt': now.toIso8601String(),
          });
          return true;
        }

        // Determine cycles from the order:
        // 1. explicit 'cycles' field (walk-in orders)
        // 2. items[].quantity (customer orders store cycles in item quantity)
        // 3. derive from weight (max 8kg per cycle)
        int cycles = 1;
        double weight = 0;
        double currentTotal = 0;
        final orderDoc = await _firestore
            .collection('orders')
            .doc(orderId)
            .get();
        final orderData = orderDoc.data();
        if (orderData != null) {
          weight = (orderData['weight'] ?? 0).toDouble();
          cycles = (orderData['cycles'] as num?)?.toInt() ?? 0;
          currentTotal =
              ((orderData['finalAmount'] ?? orderData['totalAmount']) as num?)
                      ?.toDouble() ??
                  0;

          if (cycles <= 0) {
            final items = orderData['items'] as List<dynamic>?;
            if (items != null && items.isNotEmpty) {
              final qty = (items.first['quantity'] as num?)?.toDouble() ?? 0;
              cycles = qty.round();
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

// Update the associated order. The verified payment amount becomes the
        // customer's amountPaid; any difference against the (possibly already
        // weight-repriced) finalAmount is recorded as balanceDue/refundAmount.
        final balanceDue = FinancialSettlementEngine.balanceDue(
          finalAmount: currentTotal,
          amountPaid: paymentAmount,
        );
        final refundAmount = FinancialSettlementEngine.refundAmount(
          finalAmount: currentTotal,
          amountPaid: paymentAmount,
        );
        await _firestore.collection('orders').doc(orderId).update({
          'paymentStatus': 'Verified',
          'status': OrderStatusFlowEngine.statusPaymentVerified,
          'approvedAt': now.toIso8601String(),
          'approvedBy': adminId,
          'amountPaid': paymentAmount,
          'balanceDue': balanceDue,
          'refundAmount': refundAmount,
          'estimatedDuration': estimatedDuration,
          'updatedAt': now.toIso8601String(),
        });

        // Auto-assign the right staff for the order's phase (delivery staff for
        // a Pickup order's pickup leg, laundry worker otherwise) and release
        // through the scheduling gate if all preconditions are met.
        await OrderSchedulingGate.releaseIfEligible(_firestore, orderId);
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
        final paymentData = paymentDoc.data();
        final orderId = paymentData?['orderId'] as String?;
        final paymentType = paymentData?['paymentType'] as String? ??
            'laundry';

        if (orderId != null) {
          await _firestore.collection('orders').doc(orderId).update({
            paymentType == 'laundry'
                ? 'paymentStatus'
                : 'deliveryFeePaymentStatus': 'Rejected',
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
