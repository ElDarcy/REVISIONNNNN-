import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/delivery_model.dart';
import '../models/delivery_queue_entry_model.dart';
import '../engines/delivery_priority_engine.dart';
import '../engines/distance_engine.dart';

class DeliveryProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<DeliveryModel> _deliveries = [];
  bool _isLoading = false;
  String? _error;

  List<DeliveryModel> get deliveries => _deliveries;
  List<DeliveryModel> get sortedByPriority =>
      DeliveryPriorityEngine.sortByPriority(_deliveries);
  bool get isLoading => _isLoading;
  String? get error => _error;

  // --------------------------------------------------------------------------
  // Legacy deliveries collection (kept for backward compatibility)
  // --------------------------------------------------------------------------

  Stream<List<DeliveryModel>> streamStaffDeliveries(String staffId) {
    return _firestore
        .collection('deliveries')
        .where('staffId', isEqualTo: staffId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => DeliveryModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Stream<List<DeliveryModel>> streamAllDeliveries() {
    return _firestore
        .collection('deliveries')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => DeliveryModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<bool> createDelivery(DeliveryModel delivery) async {
    try {
      await _firestore
          .collection('deliveries')
          .doc(delivery.id)
          .set(delivery.toMap());
      return true;
    } catch (e) {
      _error = 'Failed to create delivery.';
      notifyListeners();
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // deliveryQueue (source of truth for delivery tasks)
  // --------------------------------------------------------------------------

  /// Streams the entire deliveryQueue sorted by priority then FIFO.
  Stream<List<DeliveryQueueEntry>> streamDeliveryQueue() {
    return _firestore
        .collection('deliveryQueue')
        .snapshots()
        .map((snapshot) {
          final entries = snapshot.docs
              .map((doc) => DeliveryQueueEntry.fromMap(doc.data(), doc.id))
              .toList();
          entries.sort((a, b) {
            final scoreCompare = a.priorityScore.compareTo(b.priorityScore);
            if (scoreCompare != 0) return scoreCompare;
            return (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(
                  b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                );
          });
          return entries;
        })
        .handleError((error) {
          debugPrint('streamDeliveryQueue error: $error');
          return <DeliveryQueueEntry>[];
        });
  }

  /// Auto-inserts an order into the deliveryQueue when it reaches
  /// 'Ready for Delivery'. Uses `deliveryQueue/{orderId}` as the document ID
  /// so each order can only ever have one entry (duplicate prevention), and
  /// uses a transaction/atomic set to guard against simultaneous creation.
  Future<void> addToDeliveryQueue(String orderId) async {
    try {
      final orderDoc = await _firestore.collection('orders').doc(orderId).get();
      if (!orderDoc.exists) return;
      final data = orderDoc.data()!;

      final queueRef = _firestore.collection('deliveryQueue').doc(orderId);
      final queueSnap = await queueRef.get();
      if (queueSnap.exists) return; // Duplicate prevention

      final lat = (data['customerLatitude'] ?? 0).toDouble();
      final lng = (data['customerLongitude'] ?? 0).toDouble();
      final distance = lat == 0 && lng == 0
          ? 0.0
          : DistanceEngine.distanceFromShop(lat, lng);

      final entry = DeliveryQueueEntry(
        orderId: orderId,
        transactionNumber: data['transactionNumber'],
        customerId: data['userId'],
        customerName: data['customerName'],
        type: 'delivery',
        address: data['deliveryAddress'] != null
            ? (data['deliveryAddress'] is Map
                  ? (data['deliveryAddress'] as Map)['fullAddress'] ??
                        (data['deliveryAddress'] as Map)['street']
                  : null)
            : null,
        latitude: lat,
        longitude: lng,
        distanceKm: distance,
        priorityScore: 50,
        status: 'Pending Delivery',
        createdAt: DateTime.now(),
      );

      // Atomic set on the fixed orderId doc prevents duplicate creation.
      await queueRef.set(entry.toMap(), SetOptions(merge: false));
    } catch (e) {
      debugPrint('addToDeliveryQueue error: $e');
    }
  }

  /// Start a delivery without changing the laundry-processing status.
  ///
  /// `orders.status` drives the customer laundry progress. Delivery is a
  /// separate fulfilment concern, so writing `Out for Delivery` there makes a
  /// completed laundry look like it has left its progress flow.
  Future<bool> startDelivery(String orderId, String staffId) async {
    try {
      final now = Timestamp.now();
      await _firestore.collection('deliveryQueue').doc(orderId).update({
        'status': 'Out for Delivery',
        'assignedTo': staffId,
        'startedAt': now,
      });
      await _firestore.collection('orders').doc(orderId).update({
        'deliveryStatus': 'Out for Delivery',
        'assignedDeliveryStaffId': staffId,
        'deliveryStartedAt': now,
        'updatedAt': now,
      });
      return true;
    } catch (e) {
      _error = 'Failed to start delivery.';
      notifyListeners();
      return false;
    }
  }

/// Complete a delivery. Marks the queue entry done and finalizes the parent
  /// order as Completed. Refuses to complete while a balance is still owed and
  /// uncollected, so a delivery can never be finished on an unsettled bill.
  Future<bool> completeDelivery(String orderId) async {
    try {
      final now = Timestamp.now();
      final orderSnap = await _firestore.collection('orders').doc(orderId).get();
      if (orderSnap.exists) {
        final data = orderSnap.data()!;
        final amountPaid = (data['amountPaid'] as num?)?.toDouble() ?? 0;
        final finalAmount =
            (data['finalAmount'] ?? data['totalAmount'] as num?)?.toDouble() ?? 0;
        final balanceDue = (data['balanceDue'] as num?)?.toDouble() ?? 0;
        if (finalAmount > 0 &&
            (balanceDue > 0 || amountPaid + 1e-9 < finalAmount)) {
          _error = 'Collect the balance before completing delivery.';
          notifyListeners();
          return false;
        }
      }

      await _firestore.collection('deliveryQueue').doc(orderId).update({
        'status': 'Completed',
        'completedAt': now,
      });
      await _firestore.collection('orders').doc(orderId).update({
        'deliveryStatus': 'Delivered',
        'deliveredAt': now,
        'status': 'Completed',
        'completedAt': now,
        'updatedAt': now,
      });
      return true;
    } catch (e) {
      _error = 'Failed to complete delivery.';
      notifyListeners();
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // Legacy delivery status update (kept)
  // --------------------------------------------------------------------------

  Future<bool> updateDeliveryStatus(String deliveryId, String status) async {
    try {
      await _firestore.collection('deliveries').doc(deliveryId).update({
        'status': status,
      });

      if (status == 'In Transit') {
        await _firestore.collection('deliveries').doc(deliveryId).update({
          'pickedUpAt': DateTime.now().toIso8601String(),
        });
      } else if (status == 'Delivered') {
        await _firestore.collection('deliveries').doc(deliveryId).update({
          'deliveredAt': DateTime.now().toIso8601String(),
        });
      }
      return true;
    } catch (e) {
      _error = 'Failed to update delivery.';
      notifyListeners();
      return false;
    }
  }

  Future<void> loadDeliveries() async {
    _isLoading = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('deliveries')
          .orderBy('createdAt', descending: true)
          .get();
      _deliveries = snapshot.docs
          .map((doc) => DeliveryModel.fromMap(doc.data(), doc.id))
          .toList();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load deliveries.';
      _isLoading = false;
      notifyListeners();
    }
  }
}
