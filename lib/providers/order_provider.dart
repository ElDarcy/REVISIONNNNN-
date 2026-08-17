import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/order_model.dart';
import '../models/order_item_model.dart';
import '../models/order_load_model.dart';
import '../models/laundry_status_model.dart';
import '../engines/distance_engine.dart';
import '../engines/delivery_fee_engine.dart';
import '../engines/service_time_estimator.dart';
import '../engines/order_status_flow_engine.dart';
import '../engines/order_load_engine.dart';
import '../engines/order_scheduling_gate.dart';

class OrderProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  List<OrderModel> _orders = [];
  List<OrderModel> _userOrders = [];
  OrderModel? _currentOrder;
  bool _isLoading = false;
  String? _error;

  List<OrderModel> get orders => _orders;
  List<OrderModel> get userOrders => _userOrders;
  OrderModel? get currentOrder => _currentOrder;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Stream<List<OrderModel>> streamUserOrders(String userId) {
    if (userId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('orders')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
              .toList(),
        )
        .handleError((error) {
          debugPrint('streamUserOrders error: $error');
          return <OrderModel>[];
        });
  }

  Stream<List<OrderModel>> streamAllOrders() {
    return _firestore
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
              .toList(),
        )
        .handleError((error) {
          debugPrint('streamAllOrders error: $error');
          return <OrderModel>[];
        });
  }

  Stream<List<OrderModel>> streamStaffOrders(String staffId) {
    if (staffId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('orders')
        .where('assignedTo', isEqualTo: staffId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
              .toList(),
        )
        .handleError((error) {
          debugPrint('streamStaffOrders error: $error');
          return <OrderModel>[];
        });
  }

  Future<OrderModel?> getOrderById(String orderId) async {
    try {
      final doc = await _firestore.collection('orders').doc(orderId).get();
      if (doc.exists) {
        return OrderModel.fromMap(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      _error = 'Failed to load order.';
      notifyListeners();
      return null;
    }
  }

  /// Stream a single order document in real time so the tracking
  /// screen updates live when the admin approves the order.
  Stream<OrderModel?> streamOrderById(String orderId) {
    return _firestore
        .collection('orders')
        .doc(orderId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          return OrderModel.fromMap(doc.data()!, doc.id);
        })
        .handleError((error) {
          debugPrint('streamOrderById error: $error');
          return null;
        });
  }

  /// Admin approves an order to start the laundry timer.
  /// Sets approvedAt, estimatedDuration (38 min/cycle), and
  /// estimatedFinishTime = approvedAt + estimatedDuration.
  Future<bool> approveOrder(String orderId, String adminId) async {
    try {
      final now = DateTime.now();
      final doc = await _firestore.collection('orders').doc(orderId).get();
      if (!doc.exists) return false;
      final orderData = doc.data()!;

      // Determine cycles:
      // 1. explicit 'cycles' field (walk-in orders)
      // 2. items[].quantity (customer orders store cycles in item quantity)
      // 3. derive from weight (max 8kg per cycle)
      int cycles = (orderData['cycles'] as num?)?.toInt() ?? 0;
      if (cycles <= 0) {
        final items = orderData['items'] as List<dynamic>?;
        if (items != null && items.isNotEmpty) {
          final qty = (items.first['quantity'] as num?)?.toDouble() ?? 0;
          cycles = qty.round();
        }
      }
      if (cycles <= 0) {
        final weight = (orderData['weight'] ?? 0).toDouble();
        cycles = ServiceTimeEstimator.getCycleCount(weight);
      }
      if (cycles <= 0) cycles = 1;

      // 38 MINS PER CYCLE
      final estimatedDuration = ServiceTimeEstimator.estimateMinutesForCycles(
        cycles,
      );

      // Payment approval alone must not create loads from declared weight.
      // The scheduling gate releases the order only after actual weight is approved.
      await _firestore.collection('orders').doc(orderId).update({
        'status': OrderStatusFlowEngine.statusPaymentVerified,
        'paymentStatus': 'Verified',
        'approvedAt': now.toIso8601String(),
        'approvedBy': adminId,
        'estimatedDuration': estimatedDuration,
        'updatedAt': now.toIso8601String(),
      });
      await OrderSchedulingGate.releaseIfEligible(_firestore, orderId);

      return true;
    } catch (e) {
      _error = 'Failed to approve order.';
      notifyListeners();
      return false;
    }
  }

  /// Approve an order AND assign a staff member in a single atomic operation.
  ///
  /// Validation performed inside the transaction:
  /// - The order must exist and not be already approved (no duplicate approval).
  /// - A staff member must be selected (no approval without staff).
  /// - The order must not already have a staff assigned (no multiple
  ///   assignments).
  ///
  /// The approval and staff assignment are written together in one
  /// transaction so neither can happen without the other. The payment
  /// workflow is intentionally NOT modified here.
  Future<bool> approveAndAssignStaff({
    required String orderId,
    required String adminId,
    required String staffId,
  }) async {
    if (staffId.isEmpty) return false;
    try {
      final now = DateTime.now();
      final orderRef = _firestore.collection('orders').doc(orderId);

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(orderRef);
        if (!doc.exists) {
          throw Exception('Order does not exist');
        }
        final orderData = doc.data()!;

        // Prevent duplicate staff assignments.
        final hasAssignedStaff =
            orderData['assignedTo'] != null ||
            orderData['staffId'] != null ||
            orderData['assignedStaffId'] != null;
        if (hasAssignedStaff) {
          throw Exception('Staff already assigned to this order');
        }

        // Determine cycles (same heuristic as approveOrder).
        int cycles = (orderData['cycles'] as num?)?.toInt() ?? 0;
        if (cycles <= 0) {
          final items = orderData['items'] as List<dynamic>?;
          if (items != null && items.isNotEmpty) {
            final qty = (items.first['quantity'] as num?)?.toDouble() ?? 0;
            cycles = qty.round();
          }
        }
        if (cycles <= 0) {
          final weight = (orderData['weight'] ?? 0).toDouble();
          cycles = ServiceTimeEstimator.getCycleCount(weight);
        }
        if (cycles <= 0) cycles = 1;

        final estimatedDuration = ServiceTimeEstimator.estimateMinutesForCycles(
          cycles,
        );

        transaction.update(orderRef, {
          'status': OrderStatusFlowEngine.statusPaymentVerified,
          'assignedStaffId': staffId,
          'assignedTo': staffId,
          'staffId': staffId,
          // Only set approval info if not already present (e.g. from GCash verification).
          // NOTE: estimatedFinishTime is OMITTED to prevent premature timer start.
          'approvedAt': orderData['approvedAt'] ?? now.toIso8601String(),
          'approvedBy': orderData['approvedBy'] ?? adminId,
          'estimatedDuration': orderData['estimatedDuration'] ?? estimatedDuration,
          'updatedAt': now.toIso8601String(),
        });
      });

      await OrderSchedulingGate.releaseIfEligible(_firestore, orderId);
      return true;
    } catch (e) {
      debugPrint('approveAndAssignStaff error: $e');
      _error = 'Failed to approve and assign staff.';
      notifyListeners();
      return false;
    }
  }

  /// Stream all loads belonging to [orderId] in real time.
  Stream<List<OrderLoadModel>> streamOrderLoads(String orderId) {
    return _firestore
        .collection('orderLoads')
        .where('orderId', isEqualTo: orderId)
        .snapshots()
        .map((snapshot) {
          final loads = snapshot.docs
              .map((doc) => OrderLoadModel.fromMap(doc.data(), doc.id))
              .toList();
          loads.sort((a, b) => a.loadNumber.compareTo(b.loadNumber));
          return loads;
        })
        .handleError((error) {
          debugPrint('streamOrderLoads error: $error');
          return <OrderLoadModel>[];
        });
  }

  /// Stream a single load document in real time.
  Stream<OrderLoadModel?> streamOrderLoadById(String loadId) {
    return _firestore
        .collection('orderLoads')
        .doc(loadId)
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          return OrderLoadModel.fromMap(doc.data()!, doc.id);
        })
        .handleError((error) {
          debugPrint('streamOrderLoadById error: $error');
          return null;
        });
  }

  /// Fetch all loads for an order once (sorted by load number).
  Future<List<OrderLoadModel>> getLoadsForOrder(String orderId) async {
    try {
      final snapshot = await _firestore
          .collection('orderLoads')
          .where('orderId', isEqualTo: orderId)
          .get();
      final loads = snapshot.docs
          .map((doc) => OrderLoadModel.fromMap(doc.data(), doc.id))
          .toList();
      loads.sort((a, b) => a.loadNumber.compareTo(b.loadNumber));
      return loads;
    } catch (e) {
      debugPrint('getLoadsForOrder error: $e');
      return [];
    }
  }

  /// Stream ALL loads across all orders (for the staff Laundry Tasks list).
  /// Sorted by load number within each order.
  Stream<List<OrderLoadModel>> streamAllLoads() {
    return _firestore
        .collection('orderLoads')
        .snapshots()
        .map((snapshot) {
          final loads = snapshot.docs
              .map((doc) => OrderLoadModel.fromMap(doc.data(), doc.id))
              .toList();
          loads.sort((a, b) {
            if (a.orderId != b.orderId) return a.orderId.compareTo(b.orderId);
            return a.loadNumber.compareTo(b.loadNumber);
          });
          return loads;
        })
        .handleError((error) {
          debugPrint('streamAllLoads error: $error');
          return <OrderLoadModel>[];
        });
  }

  /// Mark a load as Completed and re-derive the parent order status.
  /// Used when a load reaches its ready status (Ready for Pickup/Delivery).
  /// The parent order only becomes Ready when ALL its loads are Completed.
  Future<bool> completeLoad(OrderLoadModel load) async {
    try {
      await _firestore.collection('orderLoads').doc(load.id).update({
        'status': LaundryStatus.completed.value,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      // Re-derive the parent order status from all its loads.
      final order = await getOrderById(load.orderId);
      if (order != null) {
        final allLoads = await getLoadsForOrder(load.orderId);
        final derived = OrderLoadEngine.deriveParentStatus(allLoads, order);
        await _firestore.collection('orders').doc(load.orderId).update({
          'status': derived,
          'updatedAt': DateTime.now().toIso8601String(),
        });

        // If the parent order is now ready for delivery, make sure it is in
        // the deliveryQueue so delivery staff can see it.
        if (derived == OrderStatusFlowEngine.statusReadyForDelivery) {
          await _ensureOrderInDeliveryQueue(load.orderId);
        }
      }
      return true;
    } catch (e) {
      _error = 'Failed to complete load.';
      notifyListeners();
      return false;
    }
  }

  /// Insert an order into `deliveryQueue/{orderId}` if it is not there yet.
  Future<void> _ensureOrderInDeliveryQueue(String orderId) async {
    try {
      final order = await getOrderById(orderId);
      if (order == null) return;
      final queueRef = _firestore.collection('deliveryQueue').doc(orderId);
      final existing = await queueRef.get();
      if (existing.exists) return;

      await queueRef.set({
        'orderId': orderId,
        'customerId': order.userId,
        'customerName': order.customerName ?? '',
        'address': order.deliveryAddress != null
            ? order.deliveryAddress!.toMap().toString()
            : '',
        'latitude': order.customerLatitude ?? 0,
        'longitude': order.customerLongitude ?? 0,
        'distanceKm': order.distanceKm ?? 0,
        'priorityScore': 50,
        'status': 'Pending Delivery',
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('_ensureOrderInDeliveryQueue error: $e');
    }
  }

  Future<String?> createOrder({
    required String userId,
    required List<OrderItemModel> items,
    required double weight,
    required double customerLat,
    required double customerLng,
    double? subtotal,
    double? soapTotal,
    List<Map<String, dynamic>>? selectedSoaps,
    String? notes,
    String deliveryMethod = 'Pickup',
    String orderType = 'online',
    String? customerName,
    String? customerPhone,
    String? paymentMethodOverride,
    String? paymentStatusOverride,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final orderId = _uuid.v4();

      double distance = 0;
      double deliveryFee = 0;

      // Only calculate distance/fee for Pickup
      if (deliveryMethod == 'Pickup') {
        distance = DeliveryFeeEngine.roundDistance(
          DistanceEngine.distanceFromShop(customerLat, customerLng),
        );
        deliveryFee = DeliveryFeeEngine.calculateFee(distance);
      }

      final computedSubtotal =
          subtotal ?? items.fold<double>(0, (sum, item) => sum + item.subtotal);
      final computedSoapTotal = soapTotal ?? 0;
      final total = computedSubtotal + computedSoapTotal + deliveryFee;

      final order = OrderModel(
        id: orderId,
        userId: userId,
        items: items,
        weight: weight,
        estimatedWeight: weight,
        weightStatus: 'pending',
        subtotal: computedSubtotal,
        deliveryFee: deliveryFee,
        totalAmount: total,
        deliveryMethod: deliveryMethod,
        serviceType: items.isNotEmpty ? items.first.serviceName : null,
        customerLatitude: deliveryMethod == 'Pickup' ? customerLat : null,
        customerLongitude: deliveryMethod == 'Pickup' ? customerLng : null,
        distanceKm: deliveryMethod == 'Pickup' ? distance : null,
        notes: notes,
        orderType: orderType,
        createdBy: orderType == 'walk_in' ? userId : null,
        customerName: customerName,
        customerPhone: customerPhone,
        paymentMethod: paymentMethodOverride ?? 'GCash',
        paymentStatus: paymentStatusOverride ?? 'Pending Verification',
        status: paymentStatusOverride == 'Verified'
            ? LaundryStatus.paymentVerified
            : LaundryStatus.pending,
      );

      await _firestore.collection('orders').doc(orderId).set(order.toMap());
      if (order.paymentStatus == 'Verified') {
        await OrderSchedulingGate.releaseIfEligible(_firestore, orderId);
      }
      _isLoading = false;
      notifyListeners();
      return orderId;
    } catch (e) {
      _error = 'Failed to create order.';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Saves staff camera evidence and moves the order into the admin-review
  /// state. The order is deliberately not schedulable until approval.
  Future<bool> submitWeightVerification({
    required String orderId,
    required String staffId,
    required double actualWeight,
    required String proofId,
    required String proofBase64,
  }) async {
    if (staffId.isEmpty ||
        !actualWeight.isFinite ||
        actualWeight <= 0 ||
        proofId.isEmpty ||
        proofBase64.isEmpty) {
      return false;
    }

    try {
      final now = DateTime.now();
      final orderRef = _firestore.collection('orders').doc(orderId);
      final proofRef = _firestore.collection('transaction_proofs').doc(proofId);
      await _firestore.runTransaction((transaction) async {
        final order = await transaction.get(orderRef);
        if (!order.exists) throw StateError('Order does not exist.');
        final data = order.data()!;
        final assignedStaff = data['assignedTo'] ?? data['staffId'];
        if (assignedStaff != staffId) {
          throw StateError('Order is not assigned to this staff member.');
        }
        final weightStatus = data['weightStatus'];
        if (weightStatus != 'pending' && weightStatus != 'rejected') {
          throw StateError('Weight has already been submitted.');
        }

        transaction.set(proofRef, {
          'txn_id': orderId,
          'proof_type': 'weight_verification',
          'image_base64': proofBase64,
          'submitted_by': staffId,
          'createdAt': now.toIso8601String(),
        });
        transaction.update(orderRef, {
          'actualWeight': actualWeight,
          'weightStatus': 'submitted',
          'weightProofId': proofId,
          'weightSubmittedBy': staffId,
          'weightSubmittedAt': now.toIso8601String(),
          'weightVerificationNote': null,
          'updatedAt': now.toIso8601String(),
        });
      });
      return true;
    } catch (e) {
      debugPrint('submitWeightVerification error: $e');
      _error = 'Failed to submit weight verification.';
      notifyListeners();
      return false;
    }
  }

  /// Admin decision for a submitted scale proof. Approved actual weight is
  /// released through the shared scheduling gate, which creates matching loads.
  Future<bool> verifyWeightVerification({
    required String orderId,
    required String adminId,
    required bool approved,
    String? note,
  }) async {
    if (adminId.isEmpty) return false;
    try {
      final now = DateTime.now();
      final orderRef = _firestore.collection('orders').doc(orderId);
      await _firestore.runTransaction((transaction) async {
        final order = await transaction.get(orderRef);
        if (!order.exists || order.data()!['weightStatus'] != 'submitted') {
          throw StateError('No submitted weight verification to review.');
        }
        transaction.update(orderRef, {
          'weightStatus': approved ? 'verified' : 'rejected',
          'weightVerifiedBy': approved ? adminId : null,
          'weightVerifiedAt': approved ? now.toIso8601String() : null,
          'weightVerificationNote': note?.trim().isNotEmpty == true
              ? note!.trim()
              : (approved ? null : 'Weight verification was rejected.'),
          'updatedAt': now.toIso8601String(),
        });
      });
      if (approved) {
        await OrderSchedulingGate.releaseIfEligible(_firestore, orderId);
      }
      return true;
    } catch (e) {
      debugPrint('verifyWeightVerification error: $e');
      _error = 'Failed to verify weight.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateOrderStatus(String orderId, String status) async {
    try {
      await _firestore.collection('orders').doc(orderId).update({
        'status': status,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      if (status == 'Completed') {
        await _firestore.collection('orders').doc(orderId).update({
          'completedAt': DateTime.now().toIso8601String(),
        });
      }
      return true;
    } catch (e) {
      _error = 'Failed to update status.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> assignStaff(String orderId, String staffId) async {
    try {
      await _firestore.collection('orders').doc(orderId).update({
        'assignedTo': staffId,
        'staffId': staffId,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      _error = 'Failed to assign staff.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateOrderPaymentMethod(
    String orderId,
    String paymentMethod,
    String paymentStatus,
  ) async {
    try {
      await _firestore.collection('orders').doc(orderId).update({
        'paymentMethod': paymentMethod,
        'paymentStatus': paymentStatus,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      _error = 'Failed to update payment method.';
      notifyListeners();
      return false;
    }
  }

  /// Stream the current machine queue positions for all waiting loads.
  /// Returns a map of `loadId -> queue position` (1-based). Loads waiting for
  /// a washer and loads waiting for a dryer are ranked independently using
  /// FIFO (oldest `waitingSince` first).
  Stream<Map<String, int>> streamQueuePositions() {
    return _firestore
        .collection('laundryQueue')
        .snapshots()
        .map((snapshot) {
          final washerQueue = <Map<String, dynamic>>[];
          final dryerQueue = <Map<String, dynamic>>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final loadId = data['loadId'] ?? '';
            if (loadId.toString().isEmpty) continue;
            final queueType = data['queueType'] ?? '';
            final entry = {
              'loadId': loadId.toString(),
              'queueType': queueType.toString(),
              'waitingSince': _toDateTime(data['waitingSince']),
            };
            if (queueType == 'washer') {
              washerQueue.add(entry);
            } else if (queueType == 'dryer') {
              dryerQueue.add(entry);
            }
          }
          washerQueue.sort((a, b) {
            final ad = a['waitingSince'] as DateTime?;
            final bd = b['waitingSince'] as DateTime?;
            return (ad ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
              bd ?? DateTime.fromMillisecondsSinceEpoch(0),
            );
          });
          dryerQueue.sort((a, b) {
            final ad = a['waitingSince'] as DateTime?;
            final bd = b['waitingSince'] as DateTime?;
            return (ad ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
              bd ?? DateTime.fromMillisecondsSinceEpoch(0),
            );
          });
          final result = <String, int>{};
          for (var i = 0; i < washerQueue.length; i++) {
            result[washerQueue[i]['loadId'] as String] = i + 1;
          }
          for (var i = 0; i < dryerQueue.length; i++) {
            result[dryerQueue[i]['loadId'] as String] = i + 1;
          }
          return result;
        })
        .handleError((error) {
          debugPrint('streamQueuePositions error: $error');
          return <String, int>{};
        });
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<List<OrderModel>> loadUserOrders(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('orders')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .get();
      _userOrders = snapshot.docs
          .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
          .toList();
      notifyListeners();
      return _userOrders;
    } catch (e) {
      _error = 'Failed to load orders.';
      return [];
    }
  }
}
