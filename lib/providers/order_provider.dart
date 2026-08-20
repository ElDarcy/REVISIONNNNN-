import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:uuid/uuid.dart';
import '../models/order_model.dart';
import '../models/order_item_model.dart';
import '../models/order_load_model.dart';
import '../models/laundry_status_model.dart';
import '../models/address_model.dart';
import '../engines/distance_engine.dart';
import '../engines/delivery_fee_engine.dart';
import '../engines/financial_settlement_engine.dart';
import '../engines/order_status_flow_engine.dart';
import '../engines/order_load_engine.dart';
import '../engines/order_scheduling_gate.dart';
import '../config/app_config.dart';
import '../services/notification_service.dart';

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
        .orderBy('createdAt', descending: false)
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

  /// Streams orders whose cash was collected at pickup by [collectorId]
  /// (the delivery staff who marked the pickup as collected). Callers filter
  /// client-side for cash methods and remittance state; a single-field query
  /// avoids requiring a composite index.
  ///
  /// DEBUG-INSTRUMENTED (temporary): logs every snapshot event to trace why a
  /// deleted order may still render. Remove after diagnosis.
  Stream<List<OrderModel>> streamPickupRemittances(String collectorId) {
    if (collectorId.isEmpty) return Stream.value([]);
    return _firestore
        .collection('orders')
        .where('pickupCollectedBy', isEqualTo: collectorId)
        .snapshots()
        .transform(
          StreamTransformer<QuerySnapshot<Map<String, dynamic>>, List<OrderModel>>.fromHandlers(
            handleData: (snapshot, sink) {
              debugPrint(
                '[RemitStream] project=${Firebase.app().options.projectId} '
                'db=${FirebaseFirestore.instance.databaseId} '
                'isFromCache=${snapshot.metadata.isFromCache} '
                'hasPendingWrites=${snapshot.metadata.hasPendingWrites} '
                'size=${snapshot.size}',
              );
              for (final change in snapshot.docChanges) {
                debugPrint(
                  '[RemitStream] docChange ${change.type} '
                  'orderId=${change.doc.id}',
                );
              }
              final list = snapshot.docs
                  .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
                  .toList();
              for (final order in list) {
                debugPrint(
                  '[RemitStream] order id=${order.id} '
                  'display=${order.displayNumber} '
                  'pay=${order.paymentStatus} '
                  'remit=${order.remittanceStatus}',
                );
              }
              sink.add(list);
            },
            handleError: (error, stack, sink) {
              debugPrint('[RemitStream] ERROR $error');
              sink.addError(error, stack);
            },
            handleDone: (sink) {
              debugPrint('[RemitStream] DONE (stream terminated)');
              sink.close();
            },
          ),
        )
        .handleError((error) {
          debugPrint('streamPickupRemittances error: $error');
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
      _error = 'Failed to load transaction.';
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

/// Manually assign (or re-assign) a laundry worker — an admin exception tool
  /// only. Normal flow auto-assigns staff after payment verification. This
  /// never approves the transaction or changes payment status; it only records
  /// the assignment and re-checks the scheduling gate.
  Future<bool> assignStaff({
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
          throw Exception('Transaction does not exist');
        }
        final orderData = doc.data()!;

        // Strict phase rule: a laundry staff can only be assigned once the
        // order is in the laundry-eligible phase. For a pickup order whose
        // laundry is not yet at the shop (or whose collected cash is not yet
        // remitted), only the delivery staff is assigned for the pickup leg.
        if (OrderSchedulingGate.resolveAssignmentPhase(orderData) !=
            AssignmentPhase.laundry) {
          throw StateError(
            'Laundry staff can only be assigned once the laundry is at the shop.',
          );
        }

        // Prevent overwriting existing staff assignment.
        final existingStaff =
            orderData['assignedTo'] ??
            orderData['staffId'] ??
            orderData['assignedStaffId'];
        if (existingStaff != null && (existingStaff as String).isNotEmpty) {
          // Allow if it's the same staff member (idempotent)
          if (existingStaff != staffId) {
            throw Exception(
              'Staff already assigned. Use force reassign to overwrite.',
            );
          }
        }

        // Ensure every transaction has a display number (LT-YYYYNNNN).
        final existingTxn = orderData['transactionNumber'] as String?;
        String txnNumber = existingTxn ?? '';
        if (txnNumber.isEmpty) {
          txnNumber = await _generateOrderNumber();
        }

        transaction.update(orderRef, {
          'transactionNumber': txnNumber,
          'assignedStaffId': staffId,
          'assignedTo': staffId,
          'staffId': staffId,
          'laundryStaffAssignmentSource': 'admin_override',
          'laundryStaffAssignedAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        });
      });

      // Re-check the gate: payment + weight + staff now satisfied.
      await OrderSchedulingGate.releaseIfEligible(_firestore, orderId);

      return true;
    } catch (e) {
      debugPrint('assignStaff error: $e');
      _error = 'Failed to assign staff.';
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
  /// BUG FIX: Removed automatic delivery queue creation — customer must choose fulfillment.
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
        final now = DateTime.now();
        final update = <String, dynamic>{
          'status': derived,
          'updatedAt': now.toIso8601String(),
        };
        // Set readyForPickupAt when order first reaches Ready status
        if ((derived == OrderStatusFlowEngine.statusReadyForPickup ||
                derived == OrderStatusFlowEngine.statusReadyForDelivery) &&
            order.readyForPickupAt == null) {
          final deadline = now.add(const Duration(days: 2));
          update['readyForPickupAt'] = now.toIso8601String();
          update['pickupDeadlineAt'] = deadline.toIso8601String();
        }
        await _firestore.collection('orders').doc(load.orderId).update(update);
        // NO automatic delivery queue creation — customer chooses fulfillment
      }
      return true;
    } catch (e) {
      _error = 'Failed to complete load.';
      notifyListeners();
      return false;
    }
  }

  /// Insert an order into `deliveryQueue/{orderId}` if it is not there yet.
  /// [type] must be explicitly provided: 'delivery' or 'pickup'.
  /// Automatically assigns the least-loaded delivery staff member.
  Future<void> _ensureOrderInDeliveryQueue(
    String orderId, {
    String type = 'delivery',
  }) async {
    try {
      final order = await getOrderById(orderId);
      if (order == null) return;
      final queueRef = _firestore.collection('deliveryQueue').doc(orderId);
      final existing = await queueRef.get();
      if (existing.exists) return;

      final lat = order.customerLatitude ?? 0;
      final lng = order.customerLongitude ?? 0;

      // Auto-assign the least-loaded delivery staff member.
      final assignedStaff = await _autoAssignDeliveryStaff();

      await queueRef.set({
        'orderId': orderId,
        'customerId': order.userId,
        'customerName': order.customerName ?? '',
        'type': type,
        'address': order.deliveryAddress != null
            ? order.deliveryAddress!.fullAddress
            : '',
        'latitude': lat,
        'longitude': lng,
        'distanceKm': order.distanceKm ?? 0,
        'priorityScore': 50,
        'status': 'Pending Delivery',
        'assignedTo': assignedStaff,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Also update the parent order with the delivery staff assignment.
      if (assignedStaff != null) {
        await _firestore.collection('orders').doc(orderId).update({
          'assignedDeliveryStaffId': assignedStaff,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('_ensureOrderInDeliveryQueue error: $e');
    }
  }

  /// Auto-assign the least-loaded active delivery staff member.
  /// Returns null when no delivery staff is available.
  Future<String?> _autoAssignDeliveryStaff() async {
    try {
      final usersSnap = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'delivery_staff')
          .where('isActive', isEqualTo: true)
          .get();

      if (usersSnap.docs.isEmpty) return null;
      final deliveryStaffIds = usersSnap.docs.map((d) => d.id).toList();

      // Count active deliveries per staff member.
      final queueSnap = await _firestore
          .collection('deliveryQueue')
          .where('status', whereIn: ['Pending Delivery', 'Out for Delivery'])
          .get();

      final counts = <String, int>{};
      for (final doc in queueSnap.docs) {
        final staffId = doc['assignedTo'] as String?;
        if (staffId != null && staffId.isNotEmpty) {
          counts[staffId] = (counts[staffId] ?? 0) + 1;
        }
      }

      // Pick staff with lowest active delivery count (stable sort by ID).
      deliveryStaffIds.sort((a, b) {
        final countA = counts[a] ?? 0;
        final countB = counts[b] ?? 0;
        if (countA != countB) return countA.compareTo(countB);
        return a.compareTo(b);
      });

      return deliveryStaffIds.first;
    } catch (e) {
      debugPrint('_autoAssignDeliveryStaff error: $e');
      return null;
    }
  }

  /// Generate a unique order number in LT-YYYYNNNN format using a
  /// Firestore counter document for collision-safe sequential numbering.
  Future<String> _generateOrderNumber() async {
    final year = DateTime.now().year;
    final counterRef = _firestore.collection('counters').doc('order_number_$year');
    String orderNumber = '';
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(counterRef);
      final current = snap.exists ? (snap.data()!['count'] ?? 0) as int : 0;
      final next = current + 1;
      transaction.set(counterRef, {'count': next, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      orderNumber = 'LT-$year-${next.toString().padLeft(4, '0')}';
    });
    return orderNumber;
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
    AddressModel? deliveryAddress,
    String? requestedPromoCode,
    double? promoDiscount,
    double? membershipDiscount,
    Map<String, dynamic>? pricingBreakdown,
    String? weightStatusOverride,
    double? actualWeightOverride,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final orderId = _uuid.v4();
      final transactionNumber = await _generateOrderNumber();

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
      // Apply discounts: Base → Soap → Delivery → Discounts → Final
      final effectivePromo = promoDiscount ?? 0;
      final effectiveMember = membershipDiscount ?? 0;
      final total = computedSubtotal + computedSoapTotal + deliveryFee - effectivePromo - effectiveMember;
      // Cash at Shop / walk-in orders are paid at the counter immediately, so
      // their full estimated amount is already received.
      final settledUpfront =
          paymentStatusOverride == 'Verified' ||
          paymentStatusOverride == AppConfig.paymentVerified;

      final order = OrderModel(
        id: orderId,
        transactionNumber: transactionNumber,
        userId: userId,
        items: items,
        weight: weight,
        estimatedWeight: weight,
        actualWeight: actualWeightOverride,
        weightStatus: weightStatusOverride ?? 'pending',
        subtotal: computedSubtotal,
        deliveryFee: deliveryFee,
        totalAmount: total < 0 ? 0 : total,
        finalAmount: settledUpfront ? (total < 0 ? 0 : total) : null,
        amountPaid: settledUpfront ? (total < 0 ? 0 : total) : 0,
        deliveryMethod: deliveryMethod,
        deliveryAddress: deliveryAddress,
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
        paymentStatus: paymentStatusOverride ?? (AppConfig.isCashMethod(paymentMethodOverride) ? AppConfig.paymentPendingCollection : AppConfig.paymentPending),
        status: paymentStatusOverride == 'Verified'
            ? LaundryStatus.paymentVerified
            : LaundryStatus.pending,
        soapTotal: computedSoapTotal > 0 ? computedSoapTotal : null,
        selectedSoaps: selectedSoaps?.isNotEmpty == true ? selectedSoaps : null,
        requestedPromoCode: requestedPromoCode,
        promoDiscount: effectivePromo > 0 ? effectivePromo : null,
        membershipDiscount: effectiveMember > 0 ? effectiveMember : null,
        pricingBreakdownMap: pricingBreakdown,
      );

final orderMap = order.toMap();
      // Track the pickup leg for 'Pickup' orders. The delivery staff member is
      // auto-assigned (with a pickup deliveryQueue entry) right after creation.
      if (order.deliveryMethod == 'Pickup') {
        orderMap['pickupStatus'] = 'Pending Pickup';
      }
      await _firestore.collection('orders').doc(orderId).set(orderMap);
      // Auto-assign + gate-release as soon as the order is actionable:
      // - Pickup orders always get a delivery staff assigned (the pickup leg
      //   runs regardless of payment method).
      // - Walk-in / upfront-cash orders (Verified / Pending Collection) get a
      //   laundry worker assigned so they are ready for weight verification.
      final actionable = order.deliveryMethod == 'Pickup' ||
          order.paymentStatus == 'Verified' ||
          order.paymentStatus == 'Pending Collection';
      if (actionable) {
        await OrderSchedulingGate.releaseIfEligible(_firestore, orderId);
      }
      _isLoading = false;
      notifyListeners();
      return orderId;
    } catch (e) {
      _error = 'Failed to create transaction.';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

/// Saves staff camera evidence and finalizes the actual weight.
  ///
  /// The staff's physical measurement is authoritative: the scale photo is the
  /// audit evidence and the bill is recomputed server-side from this weight.
  /// There is no separate admin weight-approval step in the processing path.
  /// The order becomes schedulable once payment and staff assignment are also
  /// satisfied (enforced by [OrderSchedulingGate.releaseIfEligible]).
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
        if (!order.exists)         throw StateError('Transaction does not exist.');
        final data = order.data()!;
        final assignedStaff = data['assignedTo'] ?? data['staffId'];
        // If no laundry worker was ever assigned, adopt the verifying staff so
        // weight verification can never be blocked by a missing assignment.
        final assignmentUpdate = <String, dynamic>{};
        if (assignedStaff is String && assignedStaff.isNotEmpty) {
          if (assignedStaff != staffId) {
            throw StateError('Transaction is not assigned to this staff member.');
          }
        } else {
          assignmentUpdate['assignedTo'] = staffId;
          assignmentUpdate['assignedStaffId'] = staffId;
          assignmentUpdate['staffId'] = staffId;
          assignmentUpdate['laundryStaffAssignmentSource'] = 'weight_submitter';
        }
        final weightStatus = data['weightStatus'];
        if (weightStatus == 'verified') {
          throw StateError('Weight has already been verified.');
        }

        transaction.set(proofRef, {
          'txn_id': orderId,
          'proof_type': 'weight_verification',
          'image_base64': proofBase64,
          'submitted_by': staffId,
          'createdAt': now.toIso8601String(),
        });
        transaction.update(orderRef, {
          ...assignmentUpdate,
          'actualWeight': actualWeight,
          'weightStatus': 'verified',
          'weightProofId': proofId,
          'weightSubmittedBy': staffId,
          'weightSubmittedAt': now.toIso8601String(),
          'weightVerifiedBy': staffId,
          'weightVerifiedAt': now.toIso8601String(),
          'weightVerificationNote': null,
          'updatedAt': now.toIso8601String(),
        });
      });
      // Release through the scheduling gate if payment and staff are set.
      await OrderSchedulingGate.releaseIfEligible(_firestore, orderId);
      return true;
    } catch (e) {
      debugPrint('submitWeightVerification error: $e');
      // A previous attempt may have committed the weight write but then failed
      // (e.g. the gate release errored). The retry then throws
      // 'Weight has already been verified.' — recover by releasing now instead
      // of failing forever.
      if ('$e'.contains('Weight has already been verified')) {
        try {
          await OrderSchedulingGate.releaseIfEligible(_firestore, orderId);
        } catch (e2) {
          debugPrint('submitWeightVerification recovery release error: $e2');
        }
        return true;
      }
      _error = 'Failed to submit weight verification.';
      notifyListeners();
      return false;
    }
  }

/// Collect a remaining balance from the customer at fulfillment (pickup or
  /// delivery). The collected amount is added to [amountPaid]; once the total
  /// received matches the final verified amount the order is financially
  /// settled. The payment method of the difference (Cash/GCash) is recorded.
  Future<bool> collectBalance({
    required String orderId,
    required String staffId,
    required double amount,
    required String method,
  }) async {
    if (staffId.isEmpty || !amount.isFinite || amount <= 0) return false;
    try {
      final now = DateTime.now();
      final orderRef = _firestore.collection('orders').doc(orderId);
      final collectionId = _uuid.v4();
      await _firestore.runTransaction((transaction) async {
        final order = await transaction.get(orderRef);
        if (!order.exists) throw StateError('Transaction does not exist.');
        final data = order.data()!;
        final amountPaid = (data['amountPaid'] as num?)?.toDouble() ?? 0;
        final finalAmount =
            (data['finalAmount'] ?? data['totalAmount'] as num?)?.toDouble() ??
                0;
        final newAmountPaid = amountPaid + amount;
        final newBalanceDue = FinancialSettlementEngine.balanceDue(
          finalAmount: finalAmount,
          amountPaid: newAmountPaid,
        );
        final settled = finalAmount <= 0 || newBalanceDue <= 0;

        transaction.update(orderRef, {
          'amountPaid': newAmountPaid,
          'balanceDue': newBalanceDue,
          'balanceSettled': settled,
          'paymentStatus': data['paymentStatus'] == 'Verified' ||
                  data['paymentStatus'] == 'Pending Collection'
              ? 'Verified'
              : data['paymentStatus'],
          'cashCollectedBy': method == 'Cash' ? staffId : (data['cashCollectedBy']),
          'cashCollectedAt': method == 'Cash' ? now.toIso8601String() : (data['cashCollectedAt']),
          'cashCollectedAmount': method == 'Cash'
              ? ((data['cashCollectedAmount'] as num?)?.toDouble() ?? 0) + amount
              : (data['cashCollectedAmount']),
          'updatedAt': now.toIso8601String(),
        });
        transaction.set(
          _firestore
              .collection('orders')
              .doc(orderId)
              .collection('balanceCollections')
              .doc(collectionId),
          {
            'orderId': orderId,
            'amount': amount,
            'method': method,
            'collectedBy': staffId,
            'collectedAt': now.toIso8601String(),
            'type': 'balance',
          },
        );
      });
      return true;
    } catch (e) {
      debugPrint('collectBalance error: $e');
      _error = 'Failed to collect balance.';
      notifyListeners();
      return false;
    }
  }

  /// Record that an overpayment ([refundAmount]) has been returned or credited
  /// to the customer. After this the order is financially settled.
  Future<bool> markRefundSettled({
    required String orderId,
    required String adminId,
    required double amount,
    String method = 'Cash',
  }) async {
    if (adminId.isEmpty || !amount.isFinite || amount <= 0) return false;
    try {
      final now = DateTime.now();
      await _firestore.collection('orders').doc(orderId).update({
        'refundSettled': true,
        'refundSettledAt': now.toIso8601String(),
        'refundSettledBy': adminId,
        'updatedAt': now.toIso8601String(),
      });
      await _firestore
          .collection('orders')
          .doc(orderId)
          .collection('balanceCollections')
          .add({
        'orderId': orderId,
        'amount': amount,
        'method': method,
        'collectedBy': adminId,
        'collectedAt': now.toIso8601String(),
        'type': 'refund',
      });
      return true;
    } catch (e) {
      debugPrint('markRefundSettled error: $e');
      _error = 'Failed to record refund.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateOrderStatus(String orderId, String status) async {
    try {
      final update = <String, dynamic>{
        'status': status,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      if (status == 'Completed') {
        update['completedAt'] = DateTime.now().toIso8601String();
      }
      await _firestore.collection('orders').doc(orderId).update(update);
      return true;
    } catch (e) {
      _error = 'Failed to update transaction status.';
      notifyListeners();
      return false;
    }
  }

  /// Cancel a transaction.
  ///
  /// - [cancelledBy] is the id of the caller (customer, admin, or staff).
  /// - Customers may only cancel before processing has started
  ///   ([OrderStatusFlowEngine.canCustomerCancel]); admins may cancel any
  ///   non-terminal order.
  /// - Any amount already paid becomes a refund due ([refundAmount]) that the
  ///   shop returns using the existing refund-settled tool.
  /// - DeliveryQueue (pickup + delivery) entries, order loads, and their
  ///   machine-queue reservations are removed so no staff or scheduler keeps
  ///   acting on a cancelled order. Loyalty points are reversed automatically
  ///   by the server-side `onOrderUpdate` Cloud Function.
  Future<bool> cancelOrder({
    required String orderId,
    required String cancelledBy,
    String? reason,
    bool isAdmin = false,
  }) async {
    try {
      final now = DateTime.now();
      final order = await getOrderById(orderId);
      if (order == null) return false;

      final terminal = order.status == LaundryStatus.completed ||
          order.status == LaundryStatus.delivered ||
          order.status == LaundryStatus.pickedUp ||
          order.status == LaundryStatus.cancelled;
      if (terminal) return false;
      if (!isAdmin && !OrderStatusFlowEngine.canCustomerCancel(order)) {
        return false;
      }

      final refund = OrderStatusFlowEngine.cancelRefundAmount(order);
      await _firestore.collection('orders').doc(orderId).update({
        'status': LaundryStatus.cancelled.value,
        'cancelledAt': now.toIso8601String(),
        'cancelledBy': cancelledBy,
        'cancellationReason': reason,
        'refundAmount': refund > 0 ? refund : (order.refundAmount ?? 0),
        'refundSettled': refund > 0 ? false : order.refundSettled,
        'updatedAt': now.toIso8601String(),
      });

      await _cleanupCancelledOrder(orderId);

      // Let the assigned staff know the task is void.
      final target = order.assignedTo ?? order.assignedDeliveryStaffId;
      if (target != null && target.isNotEmpty) {
        await NotificationService().sendNotification(
          userId: target,
          title: 'Transaction cancelled',
          body: 'Transaction ${order.displayNumber} has been cancelled.',
          type: 'operational',
          orderId: orderId,
        );
      }
      return true;
    } catch (e) {
      debugPrint('cancelOrder error: $e');
      _error = 'Failed to cancel transaction.';
      notifyListeners();
      return false;
    }
  }

  /// Best-effort cleanup of an order's active scheduling artifacts.
  Future<void> _cleanupCancelledOrder(String orderId) async {
    try {
      // Remove the pickup and final-delivery queue entries so delivery staff
      // no longer see the task.
      for (final docId in [
        orderId,
        OrderSchedulingGate.pickupQueueDocId(orderId),
      ]) {
        await _firestore.collection('deliveryQueue').doc(docId).delete();
      }
      // Remove any loads and their machine-queue reservations (idempotent:
      // pre-processing cancels have no loads yet).
      final loads = await _firestore
          .collection('orderLoads')
          .where('orderId', isEqualTo: orderId)
          .get();
      if (loads.docs.isEmpty) return;
      final loadIds = loads.docs.map((d) => d.id).toList();
      final batch = _firestore.batch();
      for (final loadId in loadIds) {
        batch.delete(_firestore.collection('orderLoads').doc(loadId));
      }
      for (var i = 0; i < loadIds.length; i += 10) {
        final end = i + 10 > loadIds.length ? loadIds.length : i + 10;
        final queueSnap = await _firestore
            .collection('laundryQueue')
            .where('loadId', whereIn: loadIds.sublist(i, end))
            .get();
        for (final doc in queueSnap.docs) {
          batch.delete(_firestore.collection('laundryQueue').doc(doc.id));
        }
      }
      await batch.commit();
    } catch (e) {
      debugPrint('_cleanupCancelledOrder error: $e');
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
      // Make the order actionable now that the payment method is set:
      // - Pickup: the delivery leg already runs regardless of payment.
      // - Drop-off cash: the server-side trigger assigns a counter worker on
      //   'Pending Collection' so they can collect the cash at the counter.
      await OrderSchedulingGate.releaseIfEligible(_firestore, orderId);
      return true;
    } catch (e) {
      _error = 'Failed to update payment method.';
      notifyListeners();
      return false;
    }
  }

  /// Staff confirms cash collection for a cash-based order.
  /// After setting paymentStatus to 'Verified', triggers the scheduling gate
  /// to create loads if the transaction is otherwise eligible.
  Future<bool> collectCashPayment({
    required String orderId,
    required String staffId,
    required double amount,
  }) async {
    try {
      await _firestore.collection('orders').doc(orderId).update({
        'paymentStatus': 'Verified',
        'cashCollectedBy': staffId,
        'cashCollectedAt': DateTime.now().toIso8601String(),
        'cashCollectedAmount': amount,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      // Now that payment is verified, try to release loads.
      await OrderSchedulingGate.releaseIfEligible(_firestore, orderId);
      return true;
    } catch (e) {
      _error = 'Failed to record cash collection.';
      notifyListeners();
      return false;
    }
  }

  /// Staff signals they have physically remitted collected cash to admin.
  ///
  /// Only the staff member who actually collected the cash may remit it:
  /// the delivery staff who collected at pickup (`pickupCollectedBy`) or the
  /// counter staff who collected at drop-off (`cashCollectedBy`). This keeps
  /// the cash handover auditable end-to-end.
  Future<bool> remitCash({
    required String orderId,
    required String staffId,
  }) async {
    try {
      final orderDoc = await _firestore.collection('orders').doc(orderId).get();
      if (!orderDoc.exists) return false;
      final data = orderDoc.data()!;
      final collector = (data['pickupCollectedBy'] as String?) ??
          (data['cashCollectedBy'] as String?);
      if (collector == null || collector.isEmpty || collector != staffId) {
        _error = 'Only the staff member who collected the cash may remit it.';
        notifyListeners();
        return false;
      }
      await _firestore.collection('orders').doc(orderId).update({
        'remittanceStatus': 'Pending Remittance',
        'remittedBy': staffId,
        'remittedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to remit cash.';
      notifyListeners();
      return false;
    }
  }

  /// Admin confirms that collected cash has been physically turned over.
  Future<bool> confirmRemittance({
    required String orderId,
    required String adminId,
  }) async {
    try {
      await _firestore.collection('orders').doc(orderId).update({
        'remittanceStatus': 'Remitted',
        'confirmedBy': adminId,
        'confirmedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
      // Cash pickup orders are now cleared for the laundry leg: auto-assign the
      // laundry worker and gate-release once weight is verified.
      await OrderSchedulingGate.releaseIfEligible(_firestore, orderId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to confirm remittance.';
      notifyListeners();
      return false;
    }
  }

  /// Delivery staff accepts and starts the pickup leg for a 'Pickup' order.
  Future<bool> startPickup({
    required String orderId,
    required String staffId,
  }) async {
    try {
      final now = DateTime.now();
      await _firestore
          .collection('deliveryQueue')
          .doc(OrderSchedulingGate.pickupQueueDocId(orderId))
          .update({
        'status': 'Pickup Assigned',
        'assignedTo': staffId,
        'startedAt': FieldValue.serverTimestamp(),
      });
      await _firestore.collection('orders').doc(orderId).update({
        'pickupStatus': 'Pickup Assigned',
        'assignedDeliveryStaffId': staffId,
        'pickupStartedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('startPickup error: $e');
      return false;
    }
  }

  /// Delivery staff marks the laundry as collected.
  ///
  /// For cash-on-pickup orders the initial estimate ([cashAmount]) is collected
  /// first (payment becomes Verified). GCash orders move straight to the
  /// laundry leg (laundry worker auto-assigned). Cash orders stay blocked until
  /// the admin confirms the staff's remittance (strict cash handover gate).
  Future<bool> completePickup({
    required String orderId,
    required String staffId,
    double? cashAmount,
  }) async {
    try {
      final now = DateTime.now();
      final isCash = cashAmount != null && cashAmount > 0;
      if (isCash) {
        final collected = await collectCashPayment(
          orderId: orderId,
          staffId: staffId,
          amount: cashAmount,
        );
        if (!collected) return false;
      }
      await _firestore
          .collection('deliveryQueue')
          .doc(OrderSchedulingGate.pickupQueueDocId(orderId))
          .update({
        'status': 'Laundry Collected',
        'completedAt': FieldValue.serverTimestamp(),
      });
      await _firestore.collection('orders').doc(orderId).update({
        'pickupStatus': 'Laundry Collected',
        'pickupCompletedAt': now.toIso8601String(),
        'pickupCollectedBy': staffId,
        'updatedAt': now.toIso8601String(),
      });
      // Non-cash pickup orders begin the laundry leg immediately.
      if (!isCash) {
        await OrderSchedulingGate.releaseIfEligible(_firestore, orderId);
      }
      return true;
    } catch (e) {
      debugPrint('completePickup error: $e');
      return false;
    }
  }

  /// Customer selects their fulfillment method after laundry is ready.
  /// [method] must be 'Personal Pickup' or 'Delivery'.
  /// If 'Delivery' is chosen, also creates the delivery queue entry.
  Future<bool> chooseFulfillment({
    required String orderId,
    required String method,
  }) async {
    if (method != 'Personal Pickup' && method != 'Delivery') return false;
    try {
      final now = DateTime.now();
      final update = <String, dynamic>{
        'fulfillmentMethod': method,
        'fulfillmentRequestedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };

      if (method == 'Delivery') {
        // Update status to Ready for Delivery
        update['status'] = OrderStatusFlowEngine.statusReadyForDelivery;
      }

      await _firestore.collection('orders').doc(orderId).update(update);

      // If customer chose delivery, create delivery queue entry
      if (method == 'Delivery') {
        await _ensureOrderInDeliveryQueue(orderId, type: 'delivery');
      }

      return true;
    } catch (e) {
      _error = 'Failed to set fulfillment method.';
      notifyListeners();
      return false;
    }
  }

  /// Get pickup credentials (QR + OTP) for personal pickup.
  Future<Map<String, dynamic>?> getPickupCredentials(String orderId) async {
    try {
      final order = await getOrderById(orderId);
      if (order == null) return null;
      // If already generated, return existing
      if (order.pickupToken != null && order.pickupCode != null) {
        return {
          'token': order.pickupToken,
          'code': order.pickupCode,
          'expiresAt': order.pickupExpiresAt,
        };
      }
      // Will be generated by the PickupService on the UI side
      return null;
    } catch (e) {
      _error = 'Failed to get pickup credentials.';
      notifyListeners();
      return null;
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
      _error = 'Failed to load transactions.';
      return [];
    }
  }
}
