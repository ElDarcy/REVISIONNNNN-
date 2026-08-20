import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../engines/order_scheduling_gate.dart';

/// Session-scoped, client-side fallback that makes sure every pickup order has
/// a `deliveryQueue` pickup entry with a delivery staff assigned to it.
///
/// This replaces the (paid) `autoAssignPickupTask` Cloud Function — which is
/// intentionally NOT deployed on the Spark plan — as the primary pickup-task
/// reconciler. It runs from the Admin Flutter Web app while an admin session is
/// open: one pass immediately on start and one on every [interval] tick.
///
/// The Delivery Staff app runs the same reconcile as a secondary safety net,
/// and [OrderSchedulingGate._assignPickupDeliveryStaff] performs the actual
/// assignment inside a Firestore transaction, so concurrent reconciles (Admin
/// Web + Delivery Staff) are idempotent: the deterministic doc id
/// (`deliveryQueue/{orderId}__pickup`) prevents duplicate entries and only one
/// client wins the assignment, so no duplicate staff assignments or duplicate
/// notifications occur.
///
/// Not tied to any widget: it is started/stopped from the auth lifecycle
/// (`AuthProvider`) so it runs on every admin screen regardless of navigation.
class PickupReconciliationService {
  PickupReconciliationService._();

  /// Shared instance. `AuthProvider` starts/stops it for admin sessions.
  static final PickupReconciliationService instance =
      PickupReconciliationService._();

  /// Overridable in tests to avoid touching Firestore. The default closure
  /// captures [FirebaseFirestore.instance] lazily so it is only resolved when a
  /// reconcile pass actually runs.
  Future<void> Function() runOnce = () =>
      OrderSchedulingGate.reconcilePendingPickups(FirebaseFirestore.instance);

  Timer? _timer;

  /// Whether a reconcile loop is currently running.
  bool get isRunning => _timer != null;

  /// Starts (or keeps) the periodic reconcile loop. Idempotent: calling while
  /// already running does not create a second timer.
  void start({Duration interval = const Duration(seconds: 45)}) {
    if (_timer != null) return;
    _runNow();
    _timer = Timer.periodic(interval, (_) => _runNow());
  }

  /// Cancels the reconcile loop. Safe to call when not running.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _runNow() {
    // Fire-and-forget: a failed pass must never block the UI or the timer.
    runOnce().catchError((Object e) {
      debugPrint('PickupReconciliationService pass error: $e');
    });
  }
}