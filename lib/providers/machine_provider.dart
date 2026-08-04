import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/machine_model.dart';
import '../models/order_model.dart';
import '../models/order_load_model.dart';
import '../engines/order_status_flow_engine.dart';
import '../engines/order_load_engine.dart';
import '../core/constants/app_constants.dart';

/// Real-time machine management provider.
///
/// - Streams all 18 machines from Firestore in real time.
/// - Assigns machines using the least-used available algorithm inside a
///   Firestore transaction so two orders can never grab the same machine.
/// - Implements system-driven scheduling: when an order reaches
///   'Payment Verified' it is auto-assigned a machine or placed in a waiting
///   queue; when a machine becomes available the next waiting order is
///   auto-assigned (queue priority = oldest first).
class MachineProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<MachineModel> _machines = [];
  bool _isLoading = false;
  String? _error;

  // Automated scheduler state.
  StreamSubscription? _schedulerSub;
  StreamSubscription? _ordersSub;
  final Map<String, String> _lastMachineStatuses = {};
  final Map<String, String> _lastOrderStatuses = {};
  bool _processingQueue = false;

  List<MachineModel> get machines => _machines;
  bool get isLoading => _isLoading;
  String? get error => _error;

  MachineProvider() {
    _startAutoScheduler();
  }

  @override
  void dispose() {
    _schedulerSub?.cancel();
    _ordersSub?.cancel();
    super.dispose();
  }

  /// Real-time stream of all machines (sorted client-side by type+number).
  Stream<List<MachineModel>> streamMachines() {
    return _firestore
        .collection('machines')
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => MachineModel.fromMap(doc.data(), doc.id))
              .toList();
          list.sort((a, b) {
            final typeCompare = a.type.compareTo(b.type);
            if (typeCompare != 0) return typeCompare;
            return a.machineNumber.compareTo(b.machineNumber);
          });
          return list;
        })
        .handleError((error) {
          debugPrint('streamMachines error: $error');
          return <MachineModel>[];
        });
  }

  Stream<List<MachineModel>> streamMachinesByType(String type) {
    return _firestore
        .collection('machines')
        .where('type', isEqualTo: type)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => MachineModel.fromMap(doc.data(), doc.id))
              .toList(),
        )
        .handleError((error) {
          debugPrint('streamMachinesByType error: $error');
          return <MachineModel>[];
        });
  }

  /// Load all machines once and cache them.
  Future<List<MachineModel>> loadMachines() async {
    _isLoading = true;
    notifyListeners();
    try {
      final snapshot = await _firestore.collection('machines').get();
      _machines = snapshot.docs
          .map((doc) => MachineModel.fromMap(doc.data(), doc.id))
          .toList();
      _machines.sort((a, b) {
        final typeCompare = a.type.compareTo(b.type);
        if (typeCompare != 0) return typeCompare;
        return a.machineNumber.compareTo(b.machineNumber);
      });
      _isLoading = false;
      notifyListeners();
      return _machines;
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to load machines.';
      notifyListeners();
      return [];
    }
  }

  /// Seed the 18 fixed machines if they do not already exist.
  /// Idempotent: existing machines are left untouched.
  Future<void> seedDefaultMachines() async {
    try {
      final snapshot = await _firestore.collection('machines').get();
      if (snapshot.docs.isNotEmpty) return;

      final batch = _firestore.batch();
      final now = DateTime.now();

      for (var i = 1; i <= AppConstants.machineWashCount; i++) {
        final id = 'wash_${i.toString().padLeft(2, '0')}';
        batch.set(
          _firestore.collection('machines').doc(id),
          MachineModel(
            id: id,
            machineId: id,
            machineNumber: i,
            type: AppConstants.machineWasher,
            status: AppConstants.machineAvailable,
            usageCount: 0,
            lastUsed: null,
            createdAt: now,
          ).toMap(),
        );
      }

      for (var i = 1; i <= AppConstants.machineDryCount; i++) {
        final id = 'dry_${i.toString().padLeft(2, '0')}';
        batch.set(
          _firestore.collection('machines').doc(id),
          MachineModel(
            id: id,
            machineId: id,
            machineNumber: i,
            type: AppConstants.machineDryer,
            status: AppConstants.machineAvailable,
            usageCount: 0,
            lastUsed: null,
            createdAt: now,
          ).toMap(),
        );
      }

      await batch.commit();
      debugPrint('Machines seeded successfully.');
    } catch (e) {
      debugPrint('seedDefaultMachines error: $e');
    }
  }

  /// Assign the best (least-used) available machine of [type] to [orderId].
  ///
  /// Process:
  /// 1. Query available machines of the required type.
  /// 2. Sort by usageCount ASC then lastUsed ASC (least-used algorithm).
  /// 3. In a transaction, re-verify the chosen machine is still available
  ///    and atomically RESERVE it (status -> reserved) + set the order status
  ///    to 'Machine Assigned' / 'Dryer Assigned'.
  ///
  /// IMPORTANT: Reservation does NOT start the cycle. The 38-minute timer only
  /// starts when staff clicks "Start Washing" / "Start Drying"
  /// (see [startMachineStep] / [startDryingStep]). usageCount and lastUsed are
  /// NOT bumped at reservation time.
  ///
  /// Returns false when no machine is available (order stays waiting).
  Future<bool> assignMachineToOrder({
    required String orderId,
    required String serviceType,
    required String targetStatus,
    String? type,
  }) async {
    // 'type' override is used for the Wash & Dry second phase (start drying)
    // where the service type alone is ambiguous; auto-detects otherwise.
    final machineType =
        type ??
        (OrderStatusFlowEngine.needsWashing(serviceType)
            ? AppConstants.machineWasher
            : AppConstants.machineDryer);

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        // 1. Query candidates (outside the transaction - queries are not
        //    allowed inside runTransaction).
        final querySnapshot = await _firestore
            .collection('machines')
            .where('type', isEqualTo: machineType)
            .get();

        final available = querySnapshot.docs.where((doc) {
          final status = (doc.data()['status'] ?? '') as String;
          return status == AppConstants.machineAvailable;
        }).toList();

        if (available.isEmpty) return false;

        // 2. Least-used ranking.
        available.sort((a, b) {
          final aUsage = ((a.data()['usageCount'] ?? 0) as num).toInt();
          final bUsage = ((b.data()['usageCount'] ?? 0) as num).toInt();
          final usageCompare = aUsage.compareTo(bUsage);
          if (usageCompare != 0) return usageCompare;

          final aLast = _toDateTime(a.data()['lastUsed']);
          final bLast = _toDateTime(b.data()['lastUsed']);
          return (aLast ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            bLast ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
        });

        final machineDoc = available.first;
        final machineId = machineDoc.id;

        // 3. Transaction: re-verify availability and atomically assign.
        final assigned = await _firestore.runTransaction((transaction) async {
          final machineRef = _firestore.collection('machines').doc(machineId);
          final machineSnap = await transaction.get(machineRef);
          if (!machineSnap.exists) return null;
          final machineData = machineSnap.data()!;
          final machineStatus = (machineData['status'] ?? '') as String;
          if (machineStatus != AppConstants.machineAvailable) {
            return null; // Taken by another order -> retry with fresh list
          }

          final machineNumber = ((machineData['machineNumber'] ?? 0) as num)
              .toInt();

          // Reserve only - do NOT set to washing/drying, do NOT bump usage.
          transaction.update(machineRef, {
            'status': AppConstants.machineReserved,
            'currentOrderId': orderId,
          });

          transaction.update(_firestore.collection('orders').doc(orderId), {
            'status': targetStatus,
            'assignedMachineId': machineId,
            'assignedMachineType': machineType,
            'assignedMachineNumber': machineNumber,
            'updatedAt': Timestamp.now(),
          });

          return machineId;
        });

        if (assigned != null) {
          debugPrint('Assigned $assigned to order $orderId');
          await logMachineActivity(
            machineId: assigned,
            orderId: orderId,
            action: AppConstants.machineLogReserved,
          );
          return true;
        }
        // else: retry once more with a freshly fetched candidate list
      } catch (e) {
        debugPrint('assignMachineToOrder attempt $attempt error: $e');
      }
    }
    return false;
  }

  /// Assign the best (least-used) available machine of [type] to a [loadId]
  /// (per-load scheduling). Updates the load record and (for backward compat)
  /// also mirrors the assignment onto the parent order doc.
  ///
  /// Returns false when no machine is available (load stays waiting).
  Future<bool> assignMachineToLoad({
    required String loadId,
    required String orderId,
    required String serviceType,
    required String targetStatus,
    String? type,
  }) async {
    final machineType =
        type ??
        (OrderStatusFlowEngine.needsWashing(serviceType)
            ? AppConstants.machineWasher
            : AppConstants.machineDryer);

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final querySnapshot = await _firestore
            .collection('machines')
            .where('type', isEqualTo: machineType)
            .get();

        final available = querySnapshot.docs.where((doc) {
          final status = (doc.data()['status'] ?? '') as String;
          return status == AppConstants.machineAvailable;
        }).toList();

        if (available.isEmpty) return false;

        available.sort((a, b) {
          final aUsage = ((a.data()['usageCount'] ?? 0) as num).toInt();
          final bUsage = ((b.data()['usageCount'] ?? 0) as num).toInt();
          final usageCompare = aUsage.compareTo(bUsage);
          if (usageCompare != 0) return usageCompare;
          final aLast = _toDateTime(a.data()['lastUsed']);
          final bLast = _toDateTime(b.data()['lastUsed']);
          return (aLast ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            bLast ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
        });

        final machineDoc = available.first;
        final machineId = machineDoc.id;

        final assigned = await _firestore.runTransaction((transaction) async {
          final machineRef = _firestore.collection('machines').doc(machineId);
          final machineSnap = await transaction.get(machineRef);
          if (!machineSnap.exists) return null;
          final machineData = machineSnap.data()!;
          if ((machineData['status'] ?? '') != AppConstants.machineAvailable) {
            return null;
          }
          final machineNumber = ((machineData['machineNumber'] ?? 0) as num)
              .toInt();

          transaction.update(machineRef, {
            'status': AppConstants.machineReserved,
            'currentOrderId': orderId,
            'currentLoadId': loadId,
          });

          transaction.update(_firestore.collection('orderLoads').doc(loadId), {
            'status': targetStatus,
            'machineId': machineId,
            'machineNumber': machineNumber,
            'machineType': machineType,
            'updatedAt': Timestamp.now(),
          });

          // Mirror onto parent order for backward compatibility.
          transaction.update(_firestore.collection('orders').doc(orderId), {
            'status': targetStatus,
            'assignedMachineId': machineId,
            'assignedMachineType': machineType,
            'assignedMachineNumber': machineNumber,
            'updatedAt': Timestamp.now(),
          });

          return machineId;
        });

        if (assigned != null) {
          debugPrint('Assigned $assigned to load $loadId (order $orderId)');
          await logMachineActivity(
            machineId: assigned,
            orderId: orderId,
            action: AppConstants.machineLogReserved,
          );
          return true;
        }
      } catch (e) {
        debugPrint('assignMachineToLoad attempt $attempt error: $e');
      }
    }
    return false;
  }

  /// Re-derive and persist the parent order status based on all its loads.
  /// Called after a load completes a step. Returns the derived status.
  Future<String> _deriveParentOrderStatus(String orderId) async {
    try {
      final orderDoc = await _firestore.collection('orders').doc(orderId).get();
      if (!orderDoc.exists) return '';
      final orderData = orderDoc.data()!;
      final order = OrderModel.fromMap(orderData, orderId);

      final loadsSnap = await _firestore
          .collection('orderLoads')
          .where('orderId', isEqualTo: orderId)
          .get();
      final loads = loadsSnap.docs
          .map((doc) => OrderLoadModel.fromMap(doc.data(), doc.id))
          .toList();

      final derived = OrderLoadEngine.deriveParentStatus(loads, order);

      final update = <String, dynamic>{
        'status': derived,
        'updatedAt': Timestamp.now(),
      };
      if (derived == OrderStatusFlowEngine.statusReadyForDelivery ||
          derived == OrderStatusFlowEngine.statusReadyForPickup) {
        // Only fire delivery queue insertion once.
        final existing = await _deliveryQueueExists(orderId);
        if (!existing) {
          await _addOrderToDeliveryQueue(orderId);
        }
      }
      await _firestore.collection('orders').doc(orderId).update(update);
      return derived;
    } catch (e) {
      debugPrint('_deriveParentOrderStatus error: $e');
      return '';
    }
  }

  /// Whether a deliveryQueue entry exists for [orderId].
  Future<bool> _deliveryQueueExists(String orderId) async {
    try {
      final doc = await _firestore
          .collection('deliveryQueue')
          .doc(orderId)
          .get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  ///
  /// Releases the assigned machine (status -> available, currentOrderId ->
  /// null) and appends it to the order's machine history.
  ///
  /// For Wash & Dry orders, when [nextStatus] is 'Waiting for Dryer', this
  /// will try to hand off to an available dryer in the same transaction.
  /// If a dryer is found it is assigned and the order moves straight to
  /// 'Drying'; otherwise the order stays 'Waiting for Dryer'.
  Future<bool> completeMachineStep({
    required String orderId,
    required String machineType,
    required String machineId,
    required String nextStatus,
    String? serviceType,
    String? loadId,
  }) async {
    try {
      // Determine whether this step hands off to a dryer (Wash & Dry).
      // Candidates are fetched BEFORE entering the transaction because
      // Firestore transactions cannot run collection queries.
      final bool shouldHandoffToDryer =
          serviceType != null &&
          OrderStatusFlowEngine.needsDrying(serviceType) &&
          nextStatus == OrderStatusFlowEngine.statusWaitingForDryer;
      final List<String> dryerCandidates = shouldHandoffToDryer
          ? await _findAvailableDryerCandidates()
          : const [];

      final result = await _firestore.runTransaction((transaction) async {
        // 1. ALL READS FIRST (Firestore requires reads before writes).
        final orderRef = _firestore.collection('orders').doc(orderId);
        final orderDoc = await transaction.get(orderRef);
        final orderData = orderDoc.data();

        DocumentSnapshot<Map<String, dynamic>>? dryerSnap;
        if (dryerCandidates.isNotEmpty) {
          dryerSnap = await transaction.get(
            _firestore.collection('machines').doc(dryerCandidates.first),
          );
        }

        // 2. THEN ALL WRITES.
        transaction.update(_firestore.collection('machines').doc(machineId), {
          'status': AppConstants.machineAvailable,
          'currentOrderId': null,
          'currentLoadId': null,
          'lastUsed': Timestamp.now(),
        });

        final List<dynamic> existingHistory =
            (orderData?['machineHistory'] as List<dynamic>?) ?? [];
        final machineNumber =
            ((orderData?['assignedMachineNumber'] ?? 0) as num).toInt();
        final machineLabel = machineType == AppConstants.machineWasher
            ? 'Wash'
            : 'Dry';
        final historyEntry = {
          'machineId': machineId,
          'type': machineType,
          'number': machineNumber,
          'label': '$machineLabel $machineNumber',
          'completedAt': Timestamp.now(),
        };
        final nextHistory = [...existingHistory, historyEntry];

        String effectiveStatus = nextStatus;
        String? dryerId;
        int? dryerNumber;

        // Wash & Dry handoff: assign the least-used available dryer if it is
        // still free (verified inside the transaction). The dryer is only
        // RESERVED (not set to drying) - the 38-minute drying timer starts only
        // when staff clicks "Start Drying" (startMachineStep). Otherwise the
        // order stays 'Waiting for Dryer' and the queue processor assigns it
        // later.
        if (dryerSnap != null && dryerSnap.exists) {
          final dryerData = dryerSnap.data()!;
          final dryerStatus = (dryerData['status'] ?? '') as String;
          if (dryerStatus == AppConstants.machineAvailable) {
            dryerId = dryerCandidates.first;
            dryerNumber = ((dryerData['machineNumber'] ?? 0) as num).toInt();

            // Reserve only - do NOT set to drying, do NOT bump usage.
            transaction.update(_firestore.collection('machines').doc(dryerId), {
              'status': AppConstants.machineReserved,
              'currentOrderId': orderId,
              'currentLoadId': loadId,
            });

            effectiveStatus = OrderStatusFlowEngine.statusDryerAssigned;
          }
        }

        // Update the load document (per-load status + machine handoff).
        if (loadId != null && loadId.isNotEmpty) {
          transaction.update(_firestore.collection('orderLoads').doc(loadId), {
            'status': effectiveStatus,
            if (dryerId != null) 'machineId': dryerId,
            if (dryerId != null) 'machineType': AppConstants.machineDryer,
            if (dryerId != null) 'machineNumber': dryerNumber,
            if (dryerId == null) 'machineId': null,
            if (dryerId == null) 'machineType': null,
            if (dryerId == null) 'machineNumber': null,
            'updatedAt': Timestamp.now(),
          });
        }

        transaction.update(orderRef, {
          // null clears the previously assigned washer when moving to dryer.
          'assignedMachineId': dryerId,
          'assignedMachineType': dryerId != null
              ? AppConstants.machineDryer
              : null,
          'assignedMachineNumber': dryerNumber,
          'machineHistory': nextHistory,
          'status': effectiveStatus,
          'updatedAt': Timestamp.now(),
        });

        // If the dryer handoff failed (no dryer available), add the order to
        // the laundryQueue for the dryer so the scheduler can assign it later.
        if (effectiveStatus == OrderStatusFlowEngine.statusWaitingForDryer) {
          await _addToLaundryQueue(orderId, AppConstants.machineDryer);
        }

        return effectiveStatus;
      });

      debugPrint('completeMachineStep -> $result');
      await logMachineActivity(
        machineId: machineId,
        orderId: orderId,
        action: AppConstants.machineLogCompleted,
      );

      // When the order becomes ready for delivery, auto-insert it into the
      // deliveryQueue so delivery staff can pick it up. Duplicate prevention
      // is handled inside addToDeliveryQueue (doc id = orderId).
      if (result == OrderStatusFlowEngine.statusReadyForDelivery) {
        await _addOrderToDeliveryQueue(orderId);
      }

      // Re-derive the parent order status from all its loads so the parent
      // reflects the aggregate progress (Ready only when ALL loads are done).
      if (loadId != null && loadId.isNotEmpty) {
        await _deriveParentOrderStatus(orderId);
      }
      return true;
    } catch (e) {
      debugPrint('completeMachineStep error: $e');
      return false;
    }
  }

  /// Query dryers that are available, ranked least-used first.
  Future<List<String>> _findAvailableDryerCandidates() async {
    try {
      final querySnapshot = await _firestore
          .collection('machines')
          .where('type', isEqualTo: AppConstants.machineDryer)
          .get();
      final available = querySnapshot.docs.where((doc) {
        final status = (doc.data()['status'] ?? '') as String;
        return status == AppConstants.machineAvailable;
      }).toList();

      available.sort((a, b) {
        final aUsage = ((a.data()['usageCount'] ?? 0) as num).toInt();
        final bUsage = ((b.data()['usageCount'] ?? 0) as num).toInt();
        final usageCompare = aUsage.compareTo(bUsage);
        if (usageCompare != 0) return usageCompare;
        final aLast = _toDateTime(a.data()['lastUsed']);
        final bLast = _toDateTime(b.data()['lastUsed']);
        return (aLast ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          bLast ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      });

      return available.map((doc) => doc.id).toList();
    } catch (e) {
      debugPrint('_findAvailableDryerCandidates error: $e');
      return [];
    }
  }

  /// Starts the system-driven scheduler.
  ///
  /// Listens to machine availability in real time. Whenever a machine
  /// transitions to `available`, the next waiting order (oldest first) is
  /// auto-assigned using the least-used algorithm. Also seeds the default
  /// machines and runs an initial queue sweep on startup.
  void _startAutoScheduler() {
    _schedulerSub = _firestore.collection('machines').snapshots().listen((
      snapshot,
    ) async {
      // Trigger queue processing whenever a machine becomes available
      // (i.e. any status transition, but only when something is available).
      final hasAvailable = snapshot.docs.any(
        (doc) => (doc.data()['status'] ?? '') == AppConstants.machineAvailable,
      );
      if (hasAvailable) {
        unawaited(_processQueueAsync());
      }

      // Detect machine becoming available (status changed to available)
      // and fire a sweep even if no machine is currently available yet
      // (handles the "machine freed" edge right when the doc updates).
      for (final doc in snapshot.docs) {
        final id = doc.id;
        final status = (doc.data()['status'] ?? '') as String;
        final previous = _lastMachineStatuses[id];
        if (previous == null) {
          _lastMachineStatuses[id] = status;
          continue;
        }
        if (previous != AppConstants.machineAvailable &&
            status == AppConstants.machineAvailable) {
          unawaited(_processQueueAsync());
        }
        _lastMachineStatuses[id] = status;
      }
    }, onError: (e) => debugPrint('Auto-scheduler listen error: $e'));

    // Initial sweep on startup.
    _firestore
        .collection('machines')
        .get()
        .then((snapshot) {
          final hasAvailable = snapshot.docs.any(
            (doc) =>
                (doc.data()['status'] ?? '') == AppConstants.machineAvailable,
          );
          if (hasAvailable) {
            unawaited(_processQueueAsync());
          }
        })
        .catchError((e) {
          debugPrint('Auto-scheduler initial sweep error: $e');
        });

    // Watch orders in real time. Whenever an order reaches 'Payment Verified'
    // (from admin approval, payment verification, or walk-in cash creation),
    // the scheduler auto-assigns the least-used available machine for it or
    // places it in the appropriate waiting queue. This makes machine
    // assignment fully system-driven with no staff interaction.
    _ordersSub = _firestore.collection('orders').snapshots().listen((
      snapshot,
    ) async {
      for (final doc in snapshot.docs) {
        final id = doc.id;
        final status = doc.data()['status'] as String? ?? '';
        final previous = _lastOrderStatuses[id];
        if (previous == null) {
          _lastOrderStatuses[id] = status;
          // Initial snapshot: schedule any order that is still Payment
          // Verified (e.g. app restarted while an order was waiting).
          if (status == OrderStatusFlowEngine.statusPaymentVerified) {
            unawaited(_scheduleVerifiedOrder(id));
          }
          continue;
        }
        if (previous != OrderStatusFlowEngine.statusPaymentVerified &&
            status == OrderStatusFlowEngine.statusPaymentVerified) {
          unawaited(_scheduleVerifiedOrder(id));
        }
        _lastOrderStatuses[id] = status;
      }
    }, onError: (e) => debugPrint('Auto-scheduler orders listen error: $e'));
  }

  /// Auto-schedule an order that has just reached 'Payment Verified'.
  ///
  /// Assigns the least-used available machine, or places the order into
  /// 'Waiting for Machine' / 'Waiting for Dryer' when no machine is free.
  /// The waiting order is then auto-assigned by the queue processor once a
  /// machine becomes available.
  Future<void> _scheduleVerifiedOrder(String orderId) async {
    try {
      final doc = await _firestore.collection('orders').doc(orderId).get();
      if (!doc.exists) return;
      final orderData = doc.data()!;
      if ((orderData['status'] ?? '') !=
          OrderStatusFlowEngine.statusPaymentVerified) {
        return;
      }
      final serviceType = OrderStatusFlowEngine.resolveServiceTypeFromData(
        orderData,
      );
      // Schedule every load of the order independently (per-load scheduling).
      await scheduleOrderLoads(orderId: orderId, serviceType: serviceType);
    } catch (e) {
      debugPrint('_scheduleVerifiedOrder error: $e');
    }
  }

  /// Schedule all loads of an order. Each load is assigned a machine
  /// independently; loads that cannot be assigned go into the waiting queue.
  Future<void> scheduleOrderLoads({
    required String orderId,
    required String serviceType,
  }) async {
    try {
      final loadsSnap = await _firestore
          .collection('orderLoads')
          .where('orderId', isEqualTo: orderId)
          .get();
      if (loadsSnap.docs.isEmpty) {
        // Fallback: no load records (legacy/single-load order) -> schedule as
        // a single order for backward compatibility.
        await scheduleOrderForMachine(
          orderId: orderId,
          serviceType: serviceType,
        );
        return;
      }

      final loads = loadsSnap.docs;
      // Small wait between assignments so concurrent transactions don't
      // collide on the same least-used machine.
      for (var i = 0; i < loads.length; i++) {
        final load = OrderLoadModel.fromMap(loads[i].data(), loads[i].id);
        if (load.status.value != OrderStatusFlowEngine.statusPaymentVerified) {
          continue;
        }
        await scheduleSingleLoad(load, orderId, serviceType);
        if (i < loads.length - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    } catch (e) {
      debugPrint('scheduleOrderLoads error: $e');
    }
  }

  /// Schedule a single load (assign a machine or place in waiting queue).
  Future<bool> scheduleSingleLoad(
    OrderLoadModel load,
    String orderId,
    String serviceType,
  ) async {
    final needsWash = OrderStatusFlowEngine.needsWashing(serviceType);
    final needsDry = OrderStatusFlowEngine.needsDrying(serviceType);

    if (needsWash) {
      final assigned = await assignMachineToLoad(
        loadId: load.id,
        orderId: orderId,
        serviceType: serviceType,
        targetStatus: OrderStatusFlowEngine.statusMachineAssigned,
        type: AppConstants.machineWasher,
      );
      if (assigned) return true;
      await _firestore.collection('orderLoads').doc(load.id).update({
        'status': OrderStatusFlowEngine.statusWaitingForMachine,
        'updatedAt': Timestamp.now(),
      });
      await _addToLaundryQueue(orderId, AppConstants.machineWasher);
      return false;
    }

    if (needsDry) {
      final assigned = await assignMachineToLoad(
        loadId: load.id,
        orderId: orderId,
        serviceType: serviceType,
        targetStatus: OrderStatusFlowEngine.statusDryerAssigned,
        type: AppConstants.machineDryer,
      );
      if (assigned) return true;
      await _firestore.collection('orderLoads').doc(load.id).update({
        'status': OrderStatusFlowEngine.statusWaitingForDryer,
        'updatedAt': Timestamp.now(),
      });
      await _addToLaundryQueue(orderId, AppConstants.machineDryer);
      return false;
    }

    return false;
  }

  /// System-driven entry point called when an order reaches `Payment Verified`
  /// (from approval, payment verification, or walk-in creation).
  ///
  /// Tries to auto-assign a machine for the order. If no machine of the
  /// required type is available, the order is placed in the appropriate
  /// waiting queue (`Waiting for Machine` / `Waiting for Dryer`). The
  /// scheduler (machine listener) will assign it when a machine frees up.
  Future<bool> scheduleOrderForMachine({
    required String orderId,
    required String serviceType,
  }) async {
    final needsWash = OrderStatusFlowEngine.needsWashing(serviceType);
    final needsDry = OrderStatusFlowEngine.needsDrying(serviceType);

    // Determine which step to schedule now.
    if (needsWash) {
      final assigned = await assignMachineToOrder(
        orderId: orderId,
        serviceType: serviceType,
        targetStatus: OrderStatusFlowEngine.statusMachineAssigned,
        type: AppConstants.machineWasher,
      );
      if (assigned) return true;
      // No washer available -> waiting queue + insert into laundryQueue.
      await _firestore.collection('orders').doc(orderId).update({
        'status': OrderStatusFlowEngine.statusWaitingForMachine,
        'updatedAt': Timestamp.now(),
      });
      await _addToLaundryQueue(orderId, AppConstants.machineWasher);
      return false;
    }

    if (needsDry) {
      final assigned = await assignMachineToOrder(
        orderId: orderId,
        serviceType: serviceType,
        targetStatus: OrderStatusFlowEngine.statusDryerAssigned,
        type: AppConstants.machineDryer,
      );
      if (assigned) return true;
      // No dryer available -> waiting queue + insert into laundryQueue.
      await _firestore.collection('orders').doc(orderId).update({
        'status': OrderStatusFlowEngine.statusWaitingForDryer,
        'updatedAt': Timestamp.now(),
      });
      await _addToLaundryQueue(orderId, AppConstants.machineDryer);
      return false;
    }

    return false;
  }

  /// Insert an order into the `laundryQueue` collection when no machine of the
  /// required type is available. Used for both washer and dryer waits.
  Future<void> _addToLaundryQueue(String orderId, String machineType) async {
    try {
      final existing = await _firestore
          .collection('laundryQueue')
          .where('orderId', isEqualTo: orderId)
          .get();
      if (existing.docs.isNotEmpty) return;

      await _firestore.collection('laundryQueue').add({
        'orderId': orderId,
        'queueType': machineType == AppConstants.machineWasher
            ? 'washer'
            : 'dryer',
        'priorityScore': 50,
        'waitingSince': Timestamp.now(),
        'createdAt': Timestamp.now(),
      });
    } catch (e) {
      debugPrint('_addToLaundryQueue error: $e');
    }
  }

  /// Insert an order into the `deliveryQueue` collection when it becomes
  /// 'Ready for Delivery'. Uses `deliveryQueue/{orderId}` as the document ID
  /// so each order can only ever have one entry (duplicate prevention).
  Future<void> _addOrderToDeliveryQueue(String orderId) async {
    try {
      final orderDoc = await _firestore.collection('orders').doc(orderId).get();
      if (!orderDoc.exists) return;
      final data = orderDoc.data()!;

      final queueRef = _firestore.collection('deliveryQueue').doc(orderId);
      final existing = await queueRef.get();
      if (existing.exists) return; // Duplicate prevention

      final lat = (data['customerLatitude'] ?? 0).toDouble();
      final lng = (data['customerLongitude'] ?? 0).toDouble();

      await queueRef.set({
        'orderId': orderId,
        'customerId': data['userId'],
        'customerName': data['customerName'],
        'address': data['customerAddress'],
        'latitude': lat,
        'longitude': lng,
        'distanceKm': 0,
        'priorityScore': 50,
        'status': 'Pending Delivery',
        'createdAt': Timestamp.now(),
      });
    } catch (e) {
      debugPrint('_addOrderToDeliveryQueue error: $e');
    }
  }

  /// Remove an order from the `laundryQueue` collection (after it has been
  /// assigned a machine or is no longer waiting).
  Future<void> _removeFromLaundryQueue(String orderId) async {
    try {
      final existing = await _firestore
          .collection('laundryQueue')
          .where('orderId', isEqualTo: orderId)
          .get();
      for (final doc in existing.docs) {
        await _firestore.collection('laundryQueue').doc(doc.id).delete();
      }
    } catch (e) {
      debugPrint('_removeFromLaundryQueue error: $e');
    }
  }

  /// Start the physical washing/drying step for a reserved machine.
  ///
  /// Called by staff via the "Start Washing"/"Start Drying" button. This is
  /// the ONLY point the 38-minute timer begins. When [loadId] is provided,
  /// the operation is applied to that load (per-load scheduling); otherwise
  /// it falls back to the parent order doc for backward compatibility.
  ///   - Machine: reserved -> washing/drying
  ///   - Load/Order: Machine Assigned -> Washing / Dryer Assigned -> Drying
  ///   - Saves cycleStart + estimatedFinish (cycleStart + 38 min)
  ///   - Bumps usageCount + lastUsed
  ///   - Logs 'Started Washing'/'Started Drying' into machine_logs
  Future<bool> startMachineStep({
    required String orderId,
    required String machineId,
    required String machineType,
    String? loadId,
  }) async {
    final now = Timestamp.now();
    final estimatedFinish = now.toDate().add(
      const Duration(minutes: AppConstants.machineCycleMinutes),
    );
    final runStatus = machineType == AppConstants.machineWasher
        ? OrderStatusFlowEngine.statusWashing
        : OrderStatusFlowEngine.statusDrying;
    try {
      await _firestore.runTransaction((transaction) async {
        final machineRef = _firestore.collection('machines').doc(machineId);
        final machineSnap = await transaction.get(machineRef);
        if (!machineSnap.exists) return;
        final data = machineSnap.data()!;
        if (data['status'] != AppConstants.machineReserved) return;

        final currentUsage = ((data['usageCount'] ?? 0) as num).toInt();
        final busy = machineType == AppConstants.machineWasher
            ? AppConstants.machineWashing
            : AppConstants.machineDrying;

        transaction.update(machineRef, {
          'status': busy,
          'usageCount': currentUsage + 1,
          'lastUsed': now,
        });

        if (loadId != null && loadId.isNotEmpty) {
          // Per-load cycle timer + status.
          transaction.update(_firestore.collection('orderLoads').doc(loadId), {
            'status': runStatus,
            'cycleStart': now,
            'estimatedFinish': estimatedFinish,
            'updatedAt': now,
          });
        }

        // Mirror onto parent order for backward compatibility.
        transaction.update(_firestore.collection('orders').doc(orderId), {
          'status': runStatus,
          'cycleStart': now,
          'estimatedFinish': estimatedFinish,
          'updatedAt': now,
        });
      });

      await logMachineActivity(
        machineId: machineId,
        orderId: orderId,
        action: machineType == AppConstants.machineWasher
            ? 'Started Washing'
            : 'Started Drying',
      );
      return true;
    } catch (e) {
      debugPrint('startMachineStep error: $e');
      return false;
    }
  }

  ///
  /// - `Waiting for Machine` orders get a washer (-> `Washing`).
  /// - `Waiting for Dryer` orders get a dryer (-> `Drying`).
  /// This preserves queue priority (FIFO by createdAt).
  Future<void> _processQueueAsync() async {
    if (_processingQueue) return;
    _processingQueue = true;
    try {
      // Fetch candidate machines (least-used first) once per type.
      final washerCandidates = await _getAvailableCandidates(
        AppConstants.machineWasher,
      );
      final dryerCandidates = await _getAvailableCandidates(
        AppConstants.machineDryer,
      );

      if (washerCandidates.isEmpty && dryerCandidates.isEmpty) return;

      // Fetch waiting orders and sort oldest-first in code (FIFO queue
      // priority). Sorting client-side avoids requiring a composite index on
      // status + createdAt in Firestore.
      final waitingSnap = await _firestore
          .collection('orders')
          .where(
            'status',
            whereIn: [
              OrderStatusFlowEngine.statusWaitingForMachine,
              OrderStatusFlowEngine.statusWaitingForDryer,
            ],
          )
          .get();

      final waitingDocs = waitingSnap.docs.toList()
        ..sort((a, b) {
          final aDate = _toDateTime(a.data()['createdAt']);
          final bDate = _toDateTime(b.data()['createdAt']);
          return (aDate ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            bDate ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
        });

      for (final doc in waitingDocs) {
        final orderData = doc.data();
        final status = orderData['status'] as String?;
        final orderId = doc.id;

        if (status == OrderStatusFlowEngine.statusWaitingForMachine) {
          if (washerCandidates.isEmpty) continue;
          final assigned = await _tryAssignFromCandidates(
            washerCandidates,
            orderId,
            OrderStatusFlowEngine.statusMachineAssigned,
          );
          if (assigned != null) {
            washerCandidates.remove(assigned);
            await _removeFromLaundryQueue(orderId);
          }
        } else if (status == OrderStatusFlowEngine.statusWaitingForDryer) {
          if (dryerCandidates.isEmpty) continue;
          final assigned = await _tryAssignFromCandidates(
            dryerCandidates,
            orderId,
            OrderStatusFlowEngine.statusDryerAssigned,
          );
          if (assigned != null) {
            dryerCandidates.remove(assigned);
            await _removeFromLaundryQueue(orderId);
          }
        }
      }
    } catch (e) {
      debugPrint('_processQueueAsync error: $e');
    } finally {
      _processingQueue = false;
    }
  }

  /// Get available machines of [type] ranked least-used first (machine ids).
  Future<List<String>> _getAvailableCandidates(String type) async {
    try {
      final querySnapshot = await _firestore
          .collection('machines')
          .where('type', isEqualTo: type)
          .get();
      final available = querySnapshot.docs.where((doc) {
        final status = (doc.data()['status'] ?? '') as String;
        return status == AppConstants.machineAvailable;
      }).toList();

      available.sort((a, b) {
        final aUsage = ((a.data()['usageCount'] ?? 0) as num).toInt();
        final bUsage = ((b.data()['usageCount'] ?? 0) as num).toInt();
        final usageCompare = aUsage.compareTo(bUsage);
        if (usageCompare != 0) return usageCompare;
        final aLast = _toDateTime(a.data()['lastUsed']);
        final bLast = _toDateTime(b.data()['lastUsed']);
        return (aLast ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          bLast ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      });

      return available.map((doc) => doc.id).toList();
    } catch (e) {
      debugPrint('_getAvailableCandidates error: $e');
      return [];
    }
  }

  /// Try to assign a specific machine [candidateIds].first to [orderId]
  /// using the transaction-based reservation. Returns the assigned machine id
  /// (or null if all candidates were taken/retries exhausted).
  Future<String?> _tryAssignFromCandidates(
    List<String> candidateIds,
    String orderId,
    String targetStatus,
  ) async {
    for (final machineId in candidateIds) {
      final assigned = await _assignSpecificMachine(
        machineId: machineId,
        orderId: orderId,
        targetStatus: targetStatus,
      );
      if (assigned != null) return machineId;
    }
    return null;
  }

  /// Atomically reserve a specific machine for an order inside a transaction.
  /// Returns the machine id when the machine was still available and assigned.
  Future<String?> _assignSpecificMachine({
    required String machineId,
    required String orderId,
    required String targetStatus,
  }) async {
    try {
      final machineRef = _firestore.collection('machines').doc(machineId);
      final machineSnap = await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(machineRef);
        if (!doc.exists) return null;
        final data = doc.data()!;
        final status = (data['status'] ?? '') as String;
        if (status != AppConstants.machineAvailable) return null;

        final machineType = data['type'] as String? ?? '';
        final machineNumber = ((data['machineNumber'] ?? 0) as num).toInt();

        // Reserve only - do NOT set to washing/drying, do NOT bump usage.
        transaction.update(machineRef, {
          'status': AppConstants.machineReserved,
          'currentOrderId': orderId,
        });

        transaction.update(_firestore.collection('orders').doc(orderId), {
          'status': targetStatus,
          'assignedMachineId': machineId,
          'assignedMachineType': machineType,
          'assignedMachineNumber': machineNumber,
          'updatedAt': Timestamp.now(),
        });

        return machineId;
      });

      if (machineSnap != null) {
        // Queue-processor assignment path: log the reservation for the
        // full audit trail (same as assignMachineToOrder).
        await logMachineActivity(
          machineId: machineId,
          orderId: orderId,
          action: AppConstants.machineLogReserved,
        );
      }
      return machineSnap;
    } catch (e) {
      debugPrint('_assignSpecificMachine error: $e');
      return null;
    }
  }

  /// Set a machine to maintenance (admin action).
  Future<bool> setMaintenance(
    String machineId, {
    bool maintenance = true,
  }) async {
    try {
      await _firestore.collection('machines').doc(machineId).update({
        'status': maintenance
            ? AppConstants.machineMaintenance
            : AppConstants.machineAvailable,
        'currentOrderId': null,
        'currentLoadId': null,
        'updatedAt': Timestamp.now(),
      });
      if (maintenance) {
        await logMachineActivity(
          machineId: machineId,
          action: AppConstants.machineLogMaintenance,
        );
      }
      return true;
    } catch (e) {
      debugPrint('setMaintenance error: $e');
      return false;
    }
  }

  /// Record a machine activity into the `machine_logs` collection.
  Future<void> logMachineActivity({
    required String machineId,
    required String action,
    String? orderId,
  }) async {
    try {
      await _firestore.collection('machine_logs').add({
        'machineId': machineId,
        'orderId': orderId,
        'action': action,
        'timestamp': Timestamp.now(),
      });
    } catch (e) {
      debugPrint('logMachineActivity error: $e');
    }
  }

  /// Real-time stream of machine activity logs (newest first).
  Stream<List<Map<String, dynamic>>> streamMachineLogs({int limit = 100}) {
    return _firestore
        .collection('machine_logs')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList())
        .handleError((error) {
          debugPrint('streamMachineLogs error: $error');
          return <Map<String, dynamic>>[];
        });
  }

  /// Reset a machine's usage counter (e.g. after maintenance).
  Future<bool> resetUsageCount(String machineId) async {
    try {
      await _firestore.collection('machines').doc(machineId).update({
        'usageCount': 0,
        'updatedAt': Timestamp.now(),
      });
      return true;
    } catch (e) {
      debugPrint('resetUsageCount error: $e');
      return false;
    }
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
