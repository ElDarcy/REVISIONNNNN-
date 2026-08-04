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
      final estimatedFinish = now.add(Duration(minutes: estimatedDuration));

      // NOTE: Machine assignment intentionally does NOT happen at approval.
      // The order moves to 'Payment Verified' and loads are created. Each
      // load is then scheduled independently (see MachineProvider).
      await _firestore.collection('orders').doc(orderId).update({
        'status': OrderStatusFlowEngine.statusPaymentVerified,
        'paymentStatus': 'Verified',
        'approvedAt': now.toIso8601String(),
        'approvedBy': adminId,
        'estimatedDuration': estimatedDuration,
        'estimatedFinishTime': estimatedFinish.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });

      // Create load records for this order (based on weight / 8kg per load).
      final orderObj = OrderModel.fromMap(orderData, orderId);
      final loadIds = await OrderLoadEngine.createLoadsForOrder(
        _firestore,
        orderObj,
      );
      if (loadIds.isNotEmpty) {
        await _firestore.collection('orders').doc(orderId).update({
          'numberOfLoads': loadIds.length,
          'updatedAt': now.toIso8601String(),
        });
      }
      return true;
    } catch (e) {
      _error = 'Failed to approve order.';
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
        subtotal: computedSubtotal,
        deliveryFee: deliveryFee,
        totalAmount: total,
        deliveryMethod: deliveryMethod,
        serviceType: items.isNotEmpty ? items.first.serviceName : null,
        customerLatitude: deliveryMethod == 'Pickup' ? customerLat : null,
        customerLongitude: deliveryMethod == 'Pickup' ? customerLng : null,
        distanceKm: deliveryMethod == 'Pickup' ? distance : null,
        notes: notes,
      );

      await _firestore.collection('orders').doc(orderId).set(order.toMap());
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
