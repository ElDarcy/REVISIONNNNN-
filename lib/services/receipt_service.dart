import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/order_model.dart';
import '../models/order_load_model.dart';
import '../models/receipt_view_data.dart';

class ReceiptService {
  ReceiptService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// Creates an opaque 256-bit token only when a QR receipt is requested.
  Future<String> ensurePublicTrackingToken(String orderId) async {
    final ref = _firestore.collection('orders').doc(orderId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (!snapshot.exists) throw StateError('Transaction not found.');
      final existing = snapshot.data()?['publicTrackingToken'] as String?;
      if (existing != null && existing.isNotEmpty) return existing;
      final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      final token = base64UrlEncode(bytes).replaceAll('=', '');
      transaction.update(ref, {'publicTrackingToken': token});
      return token;
    });
  }

  Future<ReceiptViewData> buildForOrder(OrderModel order) async {
    final results = await Future.wait([
      _firestore.collection('orderLoads').where('orderId', isEqualTo: order.id).get(),
      _staffName(order.assignedTo ?? order.staffId),
      ensurePublicTrackingToken(order.id),
    ]);
    final loadSnapshot = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final loads = loadSnapshot.docs
        .map((doc) => OrderLoadModel.fromMap(doc.data(), doc.id))
        .toList()
      ..sort((a, b) => a.loadNumber.compareTo(b.loadNumber));
    final staffName = results[1] as String;
    final token = results[2] as String;
    final fallbackLoads = loads.isEmpty
        ? <OrderLoadModel>[]
        : loads;
    return ReceiptViewData(
      transactionNumber: order.transactionNumber ?? 'Transaction ${order.id.substring(0, 6).toUpperCase()}',
      createdAt: order.createdAt,
      customerName: order.customerName,
      customerPhone: order.customerPhone,
      customerAddress: order.deliveryAddress?.fullAddress,
      serviceType: order.serviceType ?? (order.items.isNotEmpty ? order.items.first.serviceName : 'Laundry Service'),
      weight: order.weight,
      subtotal: order.subtotal,
      soapTotal: order.soapTotal,
      selectedSoaps: order.selectedSoaps,
      total: order.totalAmount,
      paymentMethod: order.paymentMethod,
      paymentMethodLabel: order.paymentMethodLabel,
      collectionMethodLabel: order.collectionMethodLabel,
      paymentStatus: order.paymentStatusDisplay,
      status: order.status.value,
      displayStatus: order.status.displayValue,
      assignedStaffName: staffName,
      loads: fallbackLoads,
      // Firebase Hosting is not configured; this is the existing project's
      // Cloud Functions HTTPS endpoint, not an invented external domain.
      trackingUrl:
          'https://us-central1-laundrycaps2.cloudfunctions.net/publicTrack?token=$token',
    );
  }

  Future<String> _staffName(String? staffId) async {
    if (staffId == null || staffId.isEmpty) return 'Not assigned';
    final doc = await _firestore.collection('users').doc(staffId).get();
    return doc.data()?['name'] as String? ?? 'Not assigned';
  }
}
