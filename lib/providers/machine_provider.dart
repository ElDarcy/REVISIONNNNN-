import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/machine_model.dart';
import '../models/order_model.dart';
import '../models/order_load_model.dart';
import '../models/maintenance_record_model.dart';
import '../models/machine_issue_model.dart';
import '../engines/order_status_flow_engine.dart';
import '../engines/order_load_engine.dart';
import '../engines/order_scheduling_gate.dart';
import '../engines/machine_assignment_engine.dart';
import '../core/constants/app_constants.dart';
import '../services/notification_service.dart';

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
  StreamSubscription? _loadsSub;
  Timer? _sweepTimer;
  final Map<String, String> _lastMachineStatuses = {};
  final Map<String, String> _lastOrderEligibility = {};
  bool _processingQueue = false;
  bool _needsReschedule = false;

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
    _loadsSub?.cancel();
    _sweepTimer?.cancel();
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
          final lastCompare = (aLast ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(bLast ?? DateTime.fromMillisecondsSinceEpoch(0));
          if (lastCompare != 0) return lastCompare;

          // Tertiary: lowest machine number
          final aMachineNum = ((a.data()['machineNumber'] ?? 0) as num).toInt();
          final bMachineNum = ((b.data()['machineNumber'] ?? 0) as num).toInt();
          return aMachineNum.compareTo(bMachineNum);
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

          // Notify Staff about assignment
          await NotificationService().sendNotification(
            userId: 'broadcast_staff', // Special keyword for all staff
            title: 'Machine Assigned',
            body:
                'Transaction #${orderId.substring(0, 6).toUpperCase()} assigned to $assigned',
            type: 'operational',
            orderId: orderId,
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
          final lastCompare = (aLast ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(bLast ?? DateTime.fromMillisecondsSinceEpoch(0));
          if (lastCompare != 0) return lastCompare;

          // Tertiary: lowest machine number
          final aMachineNum = ((a.data()['machineNumber'] ?? 0) as num).toInt();
          final bMachineNum = ((b.data()['machineNumber'] ?? 0) as num).toInt();
          return aMachineNum.compareTo(bMachineNum);
        });

        final machineDoc = available.first;
        final machineId = machineDoc.id;

        final assigned = await _firestore.runTransaction((transaction) async {
          final loadRef = _firestore.collection('orderLoads').doc(loadId);
          final loadSnap = await transaction.get(loadRef);
          if (!loadSnap.exists) return null;
          final loadData = loadSnap.data()!;
          final existingMachine = machineType == AppConstants.machineWasher
              ? loadData['washerId'] as String?
              : loadData['dryerId'] as String?;
          if (existingMachine != null && existingMachine.isNotEmpty) {
            return existingMachine;
          }
          final loadWeight = (loadData['weight'] as num?)?.toDouble();
          if (loadWeight == null ||
              !loadWeight.isFinite ||
              loadWeight <= 0 ||
              loadWeight > OrderLoadEngine.capacityKg) {
            return null;
          }
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

          // Store washer/dryer separately on the load (not a single machineId).
          final isWasher = machineType == AppConstants.machineWasher;
          transaction.update(_firestore.collection('orderLoads').doc(loadId), {
            'status': targetStatus,
            if (isWasher) 'washerId': machineId else 'dryerId': machineId,
            'updatedAt': Timestamp.now(),
          });

          // Mirror aggregated machine assignment onto the parent order for
          // backward compatibility (analytics/dashboard reads).
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

          // Notify Staff about load assignment
          await NotificationService().sendNotification(
            userId: 'broadcast_staff',
            title: 'Load Assigned',
            body:
                'Load #${loadId.substring(0, 4)} (Transaction #${orderId.substring(0, 6).toUpperCase()}) assigned to $assigned',
            type: 'operational',
            orderId: orderId,
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
  /// BUG FIX: Removed automatic delivery queue creation — customer chooses fulfillment.
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

      final now = DateTime.now();
      final update = <String, dynamic>{
        'status': derived,
        'updatedAt': Timestamp.now(),
      };
      if (derived == OrderStatusFlowEngine.statusReadyForPickup &&
          order.readyForPickupAt == null) {
        final deadline = now.add(const Duration(days: 2));
        update['readyForPickupAt'] = now.toIso8601String();
        update['pickupDeadlineAt'] = deadline.toIso8601String();
      }
      // NO automatic delivery queue creation — customer chooses fulfillment
      await _firestore.collection('orders').doc(orderId).update(update);

      // Milestone: ALL loads completed
      if (derived == OrderStatusFlowEngine.statusReadyForPickup) {
        // Notify Customer
        await NotificationService().sendNotification(
          userId: order.userId,
          title: 'Laundry Ready!',
          body: 'Your laundry is ready! Choose how to receive it.',
          type: 'milestone',
          orderId: orderId,
        );

        // Notify Staff/Admin
        await NotificationService().sendNotification(
          userId: 'broadcast_staff',
          title: 'Transaction Ready',
          body:
              'Transaction #${orderId.substring(0, 6).toUpperCase()} is ready for customer pickup.',
          type: 'operational',
          orderId: orderId,
        );
      }

      return derived;
    } catch (e) {
      debugPrint('_deriveParentOrderStatus error: $e');
      return '';
    }
  }

  /// Releases the assigned machine and appends it to the order's machine history.
  /// Re-derives parent order status from all loads.
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
      final bool shouldHandoffToDryer =
          serviceType != null &&
          OrderStatusFlowEngine.needsDrying(serviceType) &&
          nextStatus == OrderStatusFlowEngine.statusWaitingForDryer;
      final List<String> dryerCandidates = shouldHandoffToDryer
          ? await _findAvailableDryerCandidates()
          : const [];

      final result = await _firestore.runTransaction((transaction) async {
        final orderRef = _firestore.collection('orders').doc(orderId);
        final orderDoc = await transaction.get(orderRef);
        final orderData = orderDoc.data();

        DocumentSnapshot<Map<String, dynamic>>? dryerSnap;
        if (dryerCandidates.isNotEmpty) {
          dryerSnap = await transaction.get(
            _firestore.collection('machines').doc(dryerCandidates.first),
          );
        }

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

        if (dryerSnap != null && dryerSnap.exists) {
          final dryerData = dryerSnap.data()!;
          final dryerStatus = (dryerData['status'] ?? '') as String;
          if (dryerStatus == AppConstants.machineAvailable) {
            dryerId = dryerCandidates.first;
            dryerNumber = ((dryerData['machineNumber'] ?? 0) as num).toInt();

            transaction.update(_firestore.collection('machines').doc(dryerId), {
              'status': AppConstants.machineReserved,
              'currentOrderId': orderId,
              'currentLoadId': loadId,
            });

            effectiveStatus = OrderStatusFlowEngine.statusDryerAssigned;
          }
        }

        if (loadId != null && loadId.isNotEmpty) {
          final isWashStep = machineType == AppConstants.machineWasher;
          transaction.update(_firestore.collection('orderLoads').doc(loadId), {
            'status': effectiveStatus,
            if (isWashStep) 'washerId': null,
            if (isWashStep && dryerId != null) 'dryerId': dryerId,
            if (!isWashStep) 'dryerId': null,
            'updatedAt': Timestamp.now(),
          });
        }

        transaction.update(orderRef, {
          'assignedMachineId': dryerId,
          'assignedMachineType': dryerId != null
              ? AppConstants.machineDryer
              : null,
          'assignedMachineNumber': dryerNumber,
          'machineHistory': nextHistory,
          'status': effectiveStatus,
          'updatedAt': Timestamp.now(),
        });

        if (effectiveStatus == OrderStatusFlowEngine.statusWaitingForDryer) {
          await _addLoadToQueue(
            loadId: loadId ?? '',
            orderId: orderId,
            machineType: AppConstants.machineDryer,
          );
        }

        return {'status': effectiveStatus, 'dryerId': dryerId};
      });

      final String resultStatus = result['status'] as String;
      final String? assignedDryerId = result['dryerId'] as String?;

      debugPrint('completeMachineStep -> $resultStatus');
      await logMachineActivity(
        machineId: machineId,
        orderId: orderId,
        action: AppConstants.machineLogCompleted,
      );

      // NO automatic delivery queue creation — customer chooses fulfillment

      if (loadId != null && loadId.isNotEmpty) {
        await _deriveParentOrderStatus(orderId);

        // Notify Customer about load completion
        final orderDoc = await _firestore
            .collection('orders')
            .doc(orderId)
            .get();
        if (orderDoc.exists) {
          final customerId = orderDoc.data()?['userId'];
          if (customerId != null) {
            await NotificationService().sendNotification(
              userId: customerId,
              title: 'Load Finished',
              body:
                  'One of your laundry loads has finished ${machineType == AppConstants.machineWasher ? "washing" : "drying"}.',
              type: 'milestone',
              orderId: orderId,
            );
          }
        }

        // If Dryer was assigned during handoff, notify Staff
        if (resultStatus == OrderStatusFlowEngine.statusDryerAssigned &&
            assignedDryerId != null) {
          await NotificationService().sendNotification(
            userId: 'broadcast_staff',
            title: 'Dryer Assigned',
            body:
                'Load #${loadId.substring(0, 4)} assigned to $assignedDryerId',
            type: 'operational',
            orderId: orderId,
          );
        }
      }
      return true;
    } catch (e) {
      debugPrint('completeMachineStep error: $e');
      return false;
    }
  }

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
        final lastCompare = (aLast ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(bLast ?? DateTime.fromMillisecondsSinceEpoch(0));
        if (lastCompare != 0) return lastCompare;
        final aMachineNum = ((a.data()['machineNumber'] ?? 0) as num).toInt();
        final bMachineNum = ((b.data()['machineNumber'] ?? 0) as num).toInt();
        return aMachineNum.compareTo(bMachineNum);
      });

      return available.map((doc) => doc.id).toList();
    } catch (e) {
      debugPrint('_findAvailableDryerCandidates error: $e');
      return [];
    }
  }

  void _startAutoScheduler() {
    _schedulerSub = _firestore.collection('machines').snapshots().listen((
      snapshot,
    ) async {
      final hasAvailable = snapshot.docs.any(
        (doc) => (doc.data()['status'] ?? '') == AppConstants.machineAvailable,
      );
      if (hasAvailable) {
        unawaited(_processQueueAsync());
      }

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

    _ordersSub = _firestore.collection('orders').snapshots().listen((
      snapshot,
    ) async {
      for (final doc in snapshot.docs) {
        final id = doc.id;
        final data = doc.data();
        final eligibility = [
          data['status'],
          data['paymentStatus'],
          data['weightStatus'],
          data['actualWeight'],
        ].join('|');
        final previous = _lastOrderEligibility[id];
        _lastOrderEligibility[id] = eligibility;
        // Weight approval can make an order eligible while its order status
        // is already Payment Verified. Watch the complete eligibility tuple,
        // not only the status transition.
        if (previous != eligibility) {
          unawaited(_scheduleVerifiedOrder(id));
        }
      }
    }, onError: (e) => debugPrint('Auto-scheduler orders listen error: $e'));

    // Weight approval and load creation are separate Firestore operations.
    // Wake the same scheduler when the gate creates eligible loads, covering
    // the race where the order listener runs before those load documents exist.
_loadsSub = _firestore.collection('orderLoads').snapshots().listen((snapshot) {
      final hasWaitingLoad = snapshot.docs.any((doc) {
        final status = doc.data()['status'];
        return status == OrderStatusFlowEngine.statusPaymentVerified ||
            status == OrderStatusFlowEngine.statusWaitingForMachine ||
            status == OrderStatusFlowEngine.statusWaitingForDryer;
      });
      if (hasWaitingLoad) unawaited(_processQueueAsync());
    }, onError: (e) => debugPrint('Auto-scheduler loads listen error: $e'));

    // Self-healing sweep. The event-driven triggers above fire only when a
    // relevant document CHANGES while this provider is alive. If the final
    // gate-closing write (weight/payment/remittance) raced or failed silently,
    // no event ever fires again and the order is left eligible-but-loadless.
    // Sweep every 10s: release eligible load-less orders (idempotent) and
    // re-run the machine pass so processing always advances.
    _sweepTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_sweepAndSelfHeal()),
    );
  }

  /// Self-healing sweep, the fallback behind the event-driven scheduler.
  ///
  /// Only touches eligible/unassigned waiting loads and load-less eligible
  /// orders (never scans machines). Every 3s it:
  ///   1. Repairs the corrupted "Waiting for Machine/Dryer but machine already
  ///      reserved for the load" state (load actually -> Machine/Dryer Assigned).
  ///   2. Releases eligible orders that still have no loads.
  ///   3. Re-runs the guarded machine assignment pass.
  Future<void> _sweepAndSelfHeal() async {
    try {
      // 1. Waiting/unassigned loads only (single-field query, no index needed).
      final waitingLoads = await _firestore
          .collection('orderLoads')
          .where(
            'status',
            whereIn: [
              OrderStatusFlowEngine.statusPaymentVerified,
              OrderStatusFlowEngine.statusWaitingForMachine,
              OrderStatusFlowEngine.statusWaitingForDryer,
            ],
          )
          .get();

      for (final doc in waitingLoads.docs) {
        final load = OrderLoadModel.fromMap(doc.data(), doc.id);
        final orderId = load.orderId;
        final orderDoc = await _firestore
            .collection('orders')
            .doc(orderId)
            .get();
        if (!orderDoc.exists) continue;
        final orderData = orderDoc.data()!;
        final status = orderData['status'];
        if (status == 'Completed' || status == 'Cancelled') continue;

        final hasWasher = MachineAssignmentEngine.hasAssignedMachine(
          load,
          AppConstants.machineWasher,
        );
        final hasDryer = MachineAssignmentEngine.hasAssignedMachine(
          load,
          AppConstants.machineDryer,
        );

        if (load.status.value ==
                OrderStatusFlowEngine.statusWaitingForMachine &&
            hasWasher) {
          debugPrint(
            '[Sweep] Heal: load ${load.id} waiting but washer '
            '${load.assignedWasherId} assigned -> Machine Assigned',
          );
          await _firestore.collection('orderLoads').doc(load.id).update({
            'status': OrderStatusFlowEngine.statusMachineAssigned,
            'updatedAt': Timestamp.now(),
          });
          await _removeFromLaundryQueue(orderId, loadId: load.id);
          continue;
        }
        if (load.status.value ==
                OrderStatusFlowEngine.statusWaitingForDryer &&
            hasDryer) {
          debugPrint(
            '[Sweep] Heal: load ${load.id} waiting but dryer '
            '${load.assignedDryerId} assigned -> Dryer Assigned',
          );
          await _firestore.collection('orderLoads').doc(load.id).update({
            'status': OrderStatusFlowEngine.statusDryerAssigned,
            'updatedAt': Timestamp.now(),
          });
          await _removeFromLaundryQueue(orderId, loadId: load.id);
          continue;
        }
      }

      // 2. Eligible orders that still have no loads (idempotent release).
      final verified = await _firestore
          .collection('orders')
          .where('weightStatus', isEqualTo: 'verified')
          .get();
      for (final doc in verified.docs) {
        final data = doc.data();
        final status = data['status'];
        if (status == 'Completed' || status == 'Cancelled') continue;
        final hasLoads = (data['numberOfLoads'] ?? 0) > 0;
        if (!hasLoads && OrderSchedulingGate.isEligible(data)) {
          await OrderSchedulingGate.releaseIfEligible(_firestore, doc.id);
        } else if (!OrderSchedulingGate.isEligible(data)) {
          debugPrint(
            '[Sweep] Order ${doc.id} not eligible — '
            '${OrderSchedulingGate.describeBlockers(data)}',
          );
        }
      }

      // 3. Run the machine assignment pass (single writer, guarded).
      if (_processingQueue) {
        _needsReschedule = true;
      } else {
        unawaited(_processQueueAsync());
      }
    } catch (e) {
      debugPrint('_sweepAndSelfHeal error: $e');
    }
  }

  Future<void> _scheduleVerifiedOrder(String orderId) async {
    try {
      final doc = await _firestore.collection('orders').doc(orderId).get();
      if (!doc.exists) return;
      final orderData = doc.data()!;
      final actualWeight = (orderData['actualWeight'] as num?)?.toDouble();
      final paymentOk =
          orderData['paymentStatus'] == 'Verified' ||
          orderData['paymentStatus'] == 'Pending Collection';
      if ((orderData['status'] ?? '') !=
              OrderStatusFlowEngine.statusPaymentVerified ||
          !paymentOk ||
          orderData['weightStatus'] != 'verified' ||
          actualWeight == null ||
          !actualWeight.isFinite ||
          actualWeight <= 0) {
        return;
      }
      final serviceType = OrderStatusFlowEngine.resolveServiceTypeFromData(
        orderData,
      );
      await scheduleOrderLoads(orderId: orderId, serviceType: serviceType);
    } catch (e) {
      debugPrint('_scheduleVerifiedOrder error: $e');
    }
  }

  /// Enqueues the order's loads for machine scheduling. This method is NOT an
  /// assignment writer: it only moves Payment-Verified loads to a waiting
  /// state and adds them to the machine queue, then hands off to
  /// [_processQueueAsync] (the single authority that reserves machines).
  ///
  /// This single-writer design eliminates the race where two paths could
  /// assign and then revert the same load (load left "Waiting for Machine"
  /// while its washer is already reserved).
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
        debugPrint('scheduleOrderLoads: No loads found for $orderId.');
        return;
      }

      for (final doc in loadsSnap.docs) {
        final load = OrderLoadModel.fromMap(doc.data(), doc.id);
        if (load.status.value != OrderStatusFlowEngine.statusPaymentVerified) {
          continue;
        }
        await _enqueueLoadForScheduling(load, orderId, serviceType);
      }

      // Single-writer handoff: the queue processor performs all assignments.
      if (_processingQueue) {
        _needsReschedule = true;
      } else {
        unawaited(_processQueueAsync());
      }
    } catch (e) {
      debugPrint('scheduleOrderLoads error: $e');
    }
  }

  /// Marks a single Payment-Verified load as waiting and adds it to the
  /// machine queue. Idempotent: if the load already has a machine assigned,
  /// it is left in its assigned state (never reverted to waiting).
  Future<void> _enqueueLoadForScheduling(
    OrderLoadModel load,
    String orderId,
    String serviceType,
  ) async {
    final needsWash = OrderStatusFlowEngine.needsWashing(serviceType);
    final needsDry = OrderStatusFlowEngine.needsDrying(serviceType);
    final hasMachine =
        (needsWash &&
                MachineAssignmentEngine.hasAssignedMachine(
                  load,
                  AppConstants.machineWasher,
                )) ||
        (needsDry &&
                MachineAssignmentEngine.hasAssignedMachine(
                  load,
                  AppConstants.machineDryer,
                ));
    if (hasMachine) {
      debugPrint(
        'scheduleOrderLoads: Load ${load.id} already has a machine assigned.',
      );
      return;
    }

    final waitingStatus = needsWash
        ? OrderStatusFlowEngine.statusWaitingForMachine
        : OrderStatusFlowEngine.statusWaitingForDryer;
    await _firestore.collection('orderLoads').doc(load.id).update({
      'status': waitingStatus,
      'updatedAt': Timestamp.now(),
    });
    await _addLoadToQueue(
      loadId: load.id,
      orderId: orderId,
      machineType: needsWash
          ? AppConstants.machineWasher
          : AppConstants.machineDryer,
    );
  }

  Future<bool> scheduleOrderForMachine({
    required String orderId,
    required String serviceType,
  }) async {
    final needsWash = OrderStatusFlowEngine.needsWashing(serviceType);
    final needsDry = OrderStatusFlowEngine.needsDrying(serviceType);

    if (needsWash) {
      final assigned = await assignMachineToOrder(
        orderId: orderId,
        serviceType: serviceType,
        targetStatus: OrderStatusFlowEngine.statusMachineAssigned,
        type: AppConstants.machineWasher,
      );
      if (assigned) return true;
      await _firestore.collection('orders').doc(orderId).update({
        'status': OrderStatusFlowEngine.statusWaitingForMachine,
        'updatedAt': Timestamp.now(),
      });
      await _addLoadToQueue(
        orderId: orderId,
        machineType: AppConstants.machineWasher,
      );
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
      await _firestore.collection('orders').doc(orderId).update({
        'status': OrderStatusFlowEngine.statusWaitingForDryer,
        'updatedAt': Timestamp.now(),
      });
      await _addLoadToQueue(
        orderId: orderId,
        machineType: AppConstants.machineDryer,
      );
      return false;
    }

    return false;
  }

  Future<void> _addLoadToQueue({
    String loadId = '',
    required String orderId,
    required String machineType,
  }) async {
    try {
      final existing = await _firestore
          .collection('laundryQueue')
          .where(
            loadId.isNotEmpty ? 'loadId' : 'orderId',
            isEqualTo: loadId.isNotEmpty ? loadId : orderId,
          )
          .get();
      if (existing.docs.isNotEmpty) return;

      await _firestore.collection('laundryQueue').add({
        if (loadId.isNotEmpty) 'loadId': loadId,
        'orderId': orderId,
        'queueType': machineType == AppConstants.machineWasher
            ? 'washer'
            : 'dryer',
        'priorityScore': 50,
        'waitingSince': Timestamp.now(),
        'createdAt': Timestamp.now(),
      });
    } catch (e) {
      debugPrint('_addLoadToQueue error: $e');
    }
  }

  Future<void> _removeFromLaundryQueue(String orderId, {String? loadId}) async {
    try {
      final query = (loadId != null && loadId.isNotEmpty)
          ? _firestore
                .collection('laundryQueue')
                .where('loadId', isEqualTo: loadId)
          : _firestore
                .collection('laundryQueue')
                .where('orderId', isEqualTo: orderId);

      final existing = await query.get();
      for (final doc in existing.docs) {
        await _firestore.collection('laundryQueue').doc(doc.id).delete();
      }
    } catch (e) {
      debugPrint('_removeFromLaundryQueue error: $e');
    }
  }

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
        final st = data['status'] as String?;
        if (st != AppConstants.machineReserved && st != AppConstants.machineAvailable) return;

        final currentUsage = ((data['usageCount'] ?? 0) as num).toInt();
        final busy = machineType == AppConstants.machineWasher
            ? AppConstants.machineWashing
            : AppConstants.machineDrying;

        transaction.update(machineRef, {
          'status': busy,
          'usageCount': currentUsage + 1,
          'lastUsed': now,
          'currentOrderId': orderId,
          if (loadId != null && loadId.isNotEmpty) 'currentLoadId': loadId,
        });

        if (loadId != null && loadId.isNotEmpty) {
          final isWash = machineType == AppConstants.machineWasher;
          transaction.update(_firestore.collection('orderLoads').doc(loadId), {
            'status': runStatus,
            if (isWash) 'washCycleStart': now,
            if (isWash) 'washEstimatedFinish': estimatedFinish,
            if (!isWash) 'dryCycleStart': now,
            if (!isWash) 'dryEstimatedFinish': estimatedFinish,
            'updatedAt': now,
          });
        }

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

      // Milestone: Cycle Started
      final orderDoc = await _firestore.collection('orders').doc(orderId).get();
      if (orderDoc.exists) {
        final customerId = orderDoc.data()?['userId'];
        if (customerId != null) {
          await NotificationService().sendNotification(
            userId: customerId,
            title: machineType == AppConstants.machineWasher
                ? 'Washing Started'
                : 'Drying Started',
            body:
                'Your laundry has started ${machineType == AppConstants.machineWasher ? "washing" : "drying"}.',
            type: 'milestone',
            orderId: orderId,
          );
        }
      }

      return true;
    } catch (e) {
      debugPrint('startMachineStep error: $e');
      return false;
    }
  }

  Future<void> _processQueueAsync() async {
    if (_processingQueue) {
      _needsReschedule = true;
      return;
    }
    _processingQueue = true;
    try {
      debugPrint('[Scheduler] Starting queue processing pass...');

      // 1. FETCH ALL AVAILABLE CANDIDATES ONCE
      final washerCandidates = await _getAvailableCandidates(
        AppConstants.machineWasher,
      );
      final dryerCandidates = await _getAvailableCandidates(
        AppConstants.machineDryer,
      );

      debugPrint(
        '[Scheduler] Available candidates: Washers=${washerCandidates.length}, Dryers=${dryerCandidates.length}',
      );

      if (washerCandidates.isEmpty && dryerCandidates.isEmpty) {
        debugPrint('[Scheduler] No available machines. Pass finished.');
        return;
      }

      // 2. QUERY ALL WAITING LOADS
      final waitingSnap = await _firestore
          .collection('orderLoads')
          .where(
            'status',
            whereIn: [
              OrderStatusFlowEngine.statusPaymentVerified,
              OrderStatusFlowEngine.statusWaitingForMachine,
              OrderStatusFlowEngine.statusWaitingForDryer,
            ],
          )
          .get();

      final waitingDocs = waitingSnap.docs.toList();
      final waitingModels = waitingDocs
          .map((doc) => OrderLoadModel.fromMap(doc.data(), doc.id))
          .toList();
      // FIFO: oldest waiting load first (queue position #1 = oldest).
      final sortedModels = MachineAssignmentEngine.sortWaitingLoadsFifo(
        waitingModels,
      );

      debugPrint('[Scheduler] Waiting loads: ${sortedModels.length}');

      for (final load in sortedModels) {
        final status = load.status.value;
        final loadId = load.id;
        final orderId = load.orderId;
        final serviceType = load.serviceType;
        final loadNum = load.loadNumber;

        // Loads are scheduled only while the parent still satisfies the same
        // payment, staff, and verified-actual-weight gate that created them.
        final orderSnap = await _firestore.collection('orders').doc(orderId).get();
        if (!orderSnap.exists || !OrderSchedulingGate.isEligible(orderSnap.data()!)) {
          continue;
        }

        debugPrint(
          '[Scheduler] Processing load: $loadId (Order: $orderId, Load: #$loadNum, Status: $status)',
        );

        final bool needsWash =
            status == OrderStatusFlowEngine.statusWaitingForMachine ||
            (status == OrderStatusFlowEngine.statusPaymentVerified &&
                OrderStatusFlowEngine.needsWashing(serviceType));

        final bool needsDry =
            status == OrderStatusFlowEngine.statusWaitingForDryer ||
            (status == OrderStatusFlowEngine.statusPaymentVerified &&
                !OrderStatusFlowEngine.needsWashing(serviceType) &&
                OrderStatusFlowEngine.needsDrying(serviceType));

        if (needsWash) {
          if (washerCandidates.isEmpty) {
            debugPrint(
              '[Scheduler] Waiting because no candidate remains for Wash Load $loadId',
            );
            if (status == OrderStatusFlowEngine.statusPaymentVerified) {
              await _firestore.collection('orderLoads').doc(loadId).update({
                'status': OrderStatusFlowEngine.statusWaitingForMachine,
              });
            }
            continue;
          }

          final assigned = await _tryAssignLoadFromCandidates(
            washerCandidates,
            loadId: loadId,
            orderId: orderId,
            serviceType: serviceType,
            targetStatus: OrderStatusFlowEngine.statusMachineAssigned,
            machineType: AppConstants.machineWasher,
          );

          if (assigned != null) {
            debugPrint(
              '[Scheduler] Assignment committed: Washer $assigned to Load $loadId',
            );
            washerCandidates.remove(assigned);
            debugPrint(
              '[Scheduler] Remaining candidates: Washers=${washerCandidates.length}',
            );
            await _removeFromLaundryQueue(orderId, loadId: loadId);
          }
        } else if (needsDry) {
          if (dryerCandidates.isEmpty) {
            debugPrint(
              '[Scheduler] Waiting because no candidate remains for Dry Load $loadId',
            );
            if (status == OrderStatusFlowEngine.statusPaymentVerified) {
              await _firestore.collection('orderLoads').doc(loadId).update({
                'status': OrderStatusFlowEngine.statusWaitingForDryer,
              });
            }
            continue;
          }

          final machineId = dryerCandidates.first;
          debugPrint(
            '[Scheduler] Selected machine: $machineId for Dry Load $loadId',
          );

          final assigned = await _tryAssignLoadFromCandidates(
            dryerCandidates,
            loadId: loadId,
            orderId: orderId,
            serviceType: serviceType,
            targetStatus: OrderStatusFlowEngine.statusDryerAssigned,
            machineType: AppConstants.machineDryer,
          );

          if (assigned != null) {
            debugPrint(
              '[Scheduler] Assignment committed: Dryer $assigned to Load $loadId',
            );
            dryerCandidates.remove(assigned); // REMOVE FROM POOL
            debugPrint(
              '[Scheduler] Remaining candidates: Dryers=${dryerCandidates.length}',
            );
            await _removeFromLaundryQueue(orderId, loadId: loadId);
          } else {
            debugPrint(
              '[Scheduler] FAILED transaction for Dryer $machineId. Keeping in pool.',
            );
          }
        }
      }
      debugPrint('[Scheduler] Queue processing pass finished.');
    } catch (e) {
      debugPrint('_processQueueAsync error: $e');
    } finally {
      _processingQueue = false;
      if (_needsReschedule) {
        _needsReschedule = false;
        unawaited(_processQueueAsync());
      }
    }
  }

  Future<List<String>> _getAvailableCandidates(String type) async {
    try {
      final querySnapshot = await _firestore
          .collection('machines')
          .where('type', isEqualTo: type)
          .get();
      final machines = querySnapshot.docs
          .map((doc) => MachineModel.fromMap(doc.data(), doc.id))
          .toList();
      final ranked = MachineAssignmentEngine.rankAvailableMachines(
        machines,
        type,
      );
      return ranked.map((m) => m.id).toList();
    } catch (e) {
      debugPrint('_getAvailableCandidates error: $e');
      return [];
    }
  }

  Future<String?> _tryAssignLoadFromCandidates(
    List<String> candidateIds, {
    required String loadId,
    required String orderId,
    required String serviceType,
    required String targetStatus,
    required String machineType,
  }) async {
    for (final machineId in candidateIds) {
      final assigned = await _assignLoadSpecificMachine(
        machineId: machineId,
        loadId: loadId,
        orderId: orderId,
        serviceType: serviceType,
        targetStatus: targetStatus,
        machineType: machineType,
      );
      if (assigned != null) return machineId;
    }
    return null;
  }

  Future<String?> _assignLoadSpecificMachine({
    required String machineId,
    required String loadId,
    required String orderId,
    required String serviceType,
    required String targetStatus,
    required String machineType,
  }) async {
    try {
      final machineRef = _firestore.collection('machines').doc(machineId);
      final result = await _firestore.runTransaction((transaction) async {
        final loadRef = _firestore.collection('orderLoads').doc(loadId);
        final loadSnap = await transaction.get(loadRef);
        if (!loadSnap.exists) return null;
        final loadData = loadSnap.data()!;
        final existingMachine = machineType == AppConstants.machineWasher
            ? loadData['washerId'] as String?
            : loadData['dryerId'] as String?;
        if (existingMachine != null && existingMachine.isNotEmpty) {
          return existingMachine;
        }
        final loadWeight = (loadData['weight'] as num?)?.toDouble();
        if (loadWeight == null ||
            !loadWeight.isFinite ||
            loadWeight <= 0 ||
            loadWeight > OrderLoadEngine.capacityKg) {
          return null;
        }
        final doc = await transaction.get(machineRef);
        if (!doc.exists) return null;
        final data = doc.data()!;
        if ((data['status'] ?? '') != AppConstants.machineAvailable) {
          return null;
        }
        final machineNumber = ((data['machineNumber'] ?? 0) as num).toInt();
        final isWasher = machineType == AppConstants.machineWasher;

        transaction.update(machineRef, {
          'status': AppConstants.machineReserved,
          'currentOrderId': orderId,
          'currentLoadId': loadId,
        });

        transaction.update(loadRef, {
          'status': targetStatus,
          if (isWasher) 'washerId': machineId else 'dryerId': machineId,
          'updatedAt': Timestamp.now(),
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

      if (result != null) {
        await logMachineActivity(
          machineId: machineId,
          orderId: orderId,
          action: AppConstants.machineLogReserved,
        );
      }
      return result;
    } catch (e) {
      debugPrint('_assignLoadSpecificMachine error: $e');
      return null;
    }
  }

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

  Future<bool> updateMachineStatus({
    required String machineId,
    required String status,
    required bool isAdmin,
    bool force = false,
  }) async {
    if (!isAdmin) {
      debugPrint('updateMachineStatus REJECTED: not an admin');
      return false;
    }
    final allowedStatuses = {
      AppConstants.machineAvailable,
      AppConstants.machineBusy,
      AppConstants.machineMaintenance,
      AppConstants.machineInactive,
      AppConstants.machineUnderInspection,
    };
    if (!allowedStatuses.contains(status)) {
      debugPrint('updateMachineStatus REJECTED: invalid status $status');
      return false;
    }
    try {
      final machineRef = _firestore.collection('machines').doc(machineId);
      final snap = await machineRef.get();
      if (!snap.exists) return false;
      final data = snap.data()!;
      final currentStatus = (data['status'] ?? '') as String;
      final hasActiveLoad =
          data['currentOrderId'] != null || data['currentLoadId'] != null;

      if (hasActiveLoad &&
          (currentStatus == AppConstants.machineWashing ||
              currentStatus == AppConstants.machineDrying ||
              currentStatus == AppConstants.machineReserved) &&
          !force) {
        await machineRef.update({
          'pendingStatus': status,
          'updatedAt': Timestamp.now(),
        });
        debugPrint(
          'updateMachineStatus: machine $machineId has active load; '
          'queued pendingStatus=$status',
        );
        return true;
      }

      final clearsLoad =
          status == AppConstants.machineAvailable ||
          status == AppConstants.machineMaintenance ||
          status == AppConstants.machineInactive;
      await machineRef.update({
        'status': status,
        if (clearsLoad) 'currentOrderId': null,
        if (clearsLoad) 'currentLoadId': null,
        'lastUsedAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });
      await logMachineActivity(
        machineId: machineId,
        action: 'Status -> $status',
      );
      _machines = _machines
          .map((m) => m.id == machineId ? m.copyWith(status: status) : m)
          .toList();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('updateMachineStatus error: $e');
      return false;
    }
  }

  Future<String?> addMaintenanceRecord({
    required String machineId,
    required String machineType,
    required String reason,
    required String reportedBy,
    required bool isAdmin,
    DateTime? expectedCompletionDate,
    String notes = '',
  }) async {
    if (!isAdmin) {
      debugPrint('addMaintenanceRecord REJECTED: not an admin');
      return null;
    }
    try {
      final maintenanceRef = _firestore.collection('maintenanceRecords').doc();
      final record = MaintenanceRecordModel(
        maintenanceId: maintenanceRef.id,
        machineId: machineId,
        machineType: machineType,
        reason: reason,
        reportedBy: reportedBy,
        startedAt: DateTime.now(),
        expectedCompletionDate: expectedCompletionDate,
        status: AppConstants.maintenanceInProgress,
        notes: notes,
      );

      final machineRef = _firestore.collection('machines').doc(machineId);
      final snap = await machineRef.get();
      if (!snap.exists) return null;
      final data = snap.data()!;
      final currentStatus = (data['status'] ?? '') as String;
      final hasActiveLoad =
          data['currentOrderId'] != null || data['currentLoadId'] != null;

      final historyRaw = data['maintenanceHistory'] as List<dynamic>? ?? [];
      final nextHistory = [
        ...historyRaw,
        {
          'maintenanceId': maintenanceRef.id,
          'reason': reason,
          'startedAt': Timestamp.now(),
          'status': AppConstants.maintenanceInProgress,
        },
      ];

      await _firestore.runTransaction((transaction) async {
        transaction.set(maintenanceRef, record.toMap());
        if (hasActiveLoad &&
            (currentStatus == AppConstants.machineWashing ||
                currentStatus == AppConstants.machineDrying ||
                currentStatus == AppConstants.machineReserved)) {
          transaction.update(machineRef, {
            'pendingStatus': AppConstants.machineMaintenance,
            'maintenanceHistory': nextHistory,
            'updatedAt': Timestamp.now(),
          });
        } else {
          transaction.update(machineRef, {
            'status': AppConstants.machineMaintenance,
            'currentOrderId': null,
            'currentLoadId': null,
            'pendingStatus': null,
            'maintenanceHistory': nextHistory,
            'updatedAt': Timestamp.now(),
          });
        }
      });

      await logMachineActivity(
        machineId: machineId,
        action: AppConstants.machineLogMaintenance,
      );
      return maintenanceRef.id;
    } catch (e) {
      debugPrint('addMaintenanceRecord error: $e');
      return null;
    }
  }

  Future<bool> completeMaintenance({
    required String maintenanceId,
    required String machineId,
    required bool isAdmin,
  }) async {
    if (!isAdmin) {
      debugPrint('completeMaintenance REJECTED: not an admin');
      return false;
    }
    try {
      await _firestore.runTransaction((transaction) async {
        final maintenanceRef = _firestore
            .collection('maintenanceRecords')
            .doc(maintenanceId);
        transaction.update(maintenanceRef, {
          'status': AppConstants.maintenanceCompleted,
          'completedAt': Timestamp.now(),
        });

        final machineRef = _firestore.collection('machines').doc(machineId);
        transaction.update(machineRef, {
          'status': AppConstants.machineAvailable,
          'pendingStatus': null,
          'currentOrderId': null,
          'currentLoadId': null,
          'lastUsedAt': Timestamp.now(),
          'updatedAt': Timestamp.now(),
        });
      });
      await logMachineActivity(
        machineId: machineId,
        action: 'Maintenance Completed',
      );
      return true;
    } catch (e) {
      debugPrint('completeMaintenance error: $e');
      return false;
    }
  }

  Future<String?> reportMachineIssue({
    required String machineId,
    required String issueCategory,
    required String description,
    required String reportedBy,
  }) async {
    try {
      final issueRef = _firestore.collection('machineIssues').doc();
      final issue = MachineIssueModel(
        issueId: issueRef.id,
        machineId: machineId,
        issueCategory: issueCategory,
        description: description,
        reportedBy: reportedBy,
        reportedAt: DateTime.now(),
      );

      final machineRef = _firestore.collection('machines').doc(machineId);
      final snap = await machineRef.get();
      if (!snap.exists) return null;
      final data = snap.data()!;
      final currentStatus = (data['status'] ?? '') as String;
      final hasActiveLoad =
          data['currentOrderId'] != null || data['currentLoadId'] != null;

      await _firestore.runTransaction((transaction) async {
        transaction.set(issueRef, issue.toMap());
        if (hasActiveLoad &&
            (currentStatus == AppConstants.machineWashing ||
                currentStatus == AppConstants.machineDrying ||
                currentStatus == AppConstants.machineReserved)) {
          transaction.update(machineRef, {
            'pendingStatus': AppConstants.machineUnderInspection,
            'updatedAt': Timestamp.now(),
          });
        } else {
          transaction.update(machineRef, {
            'status': AppConstants.machineUnderInspection,
            'pendingStatus': null,
            'updatedAt': Timestamp.now(),
          });
        }
      });

      await logMachineActivity(
        machineId: machineId,
        action: 'Issue reported: $issueCategory',
      );
      return issueRef.id;
    } catch (e) {
      debugPrint('reportMachineIssue error: $e');
      return null;
    }
  }

  Stream<List<MaintenanceRecordModel>> streamMaintenanceRecords() {
    return _firestore
        .collection('maintenanceRecords')
        .orderBy('startedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => MaintenanceRecordModel.fromMap(doc.data(), doc.id))
              .toList(),
        )
        .handleError((error) {
          debugPrint('streamMaintenanceRecords error: $error');
          return <MaintenanceRecordModel>[];
        });
  }

  Stream<List<MachineIssueModel>> streamMachineIssues() {
    return _firestore
        .collection('machineIssues')
        .orderBy('reportedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => MachineIssueModel.fromMap(doc.data(), doc.id))
              .toList(),
        )
        .handleError((error) {
          debugPrint('streamMachineIssues error: $error');
          return <MachineIssueModel>[];
        });
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
