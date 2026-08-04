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
        customerId: data['userId'],
        customerName: data['customerName'],
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

  /// Start a delivery: set status to 'Out for Delivery' and update the order.
  Future<bool> startDelivery(String orderId, String staffId) async {
    try {
      final now = Timestamp.now();
      await _firestore.collection('deliveryQueue').doc(orderId).update({
        'status': 'Out for Delivery',
        'assignedTo': staffId,
        'startedAt': now,
      });
      await _firestore.collection('orders').doc(orderId).update({
        'status': 'Out for Delivery',
        'updatedAt': now,
      });
      return true;
    } catch (e) {
      _error = 'Failed to start delivery.';
      notifyListeners();
      return false;
    }
  }

  /// Complete a delivery: set status to 'Completed' and update the order.
  Future<bool> completeDelivery(String orderId) async {
    try {
      final now = Timestamp.now();
      await _firestore.collection('deliveryQueue').doc(orderId).update({
        'status': 'Completed',
        'completedAt': now,
      });
      await _firestore.collection('orders').doc(orderId).update({
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
