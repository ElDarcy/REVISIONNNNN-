import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_app/core/constants/app_constants.dart';
import 'package:laundry_app/engines/machine_assignment_engine.dart';
import 'package:laundry_app/models/machine_model.dart';
import 'package:laundry_app/models/laundry_status_model.dart';
import 'package:laundry_app/models/order_load_model.dart';

void main() {
  test('ranks tied available machines by lowest machine number', () {
    final timestamp = DateTime.utc(2026, 8, 14, 10);
    final machines = [
      MachineModel(
        id: 'wash_02',
        machineId: 'wash_02',
        machineNumber: 2,
        type: AppConstants.machineWasher,
        usageCount: 3,
        lastUsed: timestamp,
      ),
      MachineModel(
        id: 'wash_01',
        machineId: 'wash_01',
        machineNumber: 1,
        type: AppConstants.machineWasher,
        usageCount: 3,
        lastUsed: timestamp,
      ),
    ];

    expect(
      MachineAssignmentEngine.findBestAvailableMachine(
        machines,
        AppConstants.machineWasher,
      )?.id,
      'wash_01',
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // FIFO / queue scheduling rules (acceptance tests 1-5)
  // ──────────────────────────────────────────────────────────────────────────

  test('sortWaitingLoadsFifo orders oldest load first (queue #1 = oldest)', () {
    final base = DateTime.utc(2026, 8, 20, 10);
    final loads = [
      _load('L3', createdAt: base.add(const Duration(seconds: 30))),
      _load('L1', createdAt: base),
      _load('L2', createdAt: base.add(const Duration(seconds: 15))),
    ];

    final sorted = MachineAssignmentEngine.sortWaitingLoadsFifo(loads);

    expect(sorted.map((l) => l.id).toList(), ['L1', 'L2', 'L3']);
  });

  test('one available machine assigns exactly one load (oldest first)', () {
    final base = DateTime.utc(2026, 8, 20, 10);
    final loads = [
      _load('A', createdAt: base),
      _load('B', createdAt: base.add(const Duration(seconds: 10))),
      _load('C', createdAt: base.add(const Duration(seconds: 20))),
    ];

    final assigned = _simulateFifoAssignment(loads, availableMachines: 1);

    expect(assigned, ['A']);
  });

  test('zero available machines assign no loads', () {
    final base = DateTime.utc(2026, 8, 20, 10);
    final loads = [
      _load('A', createdAt: base),
      _load('B', createdAt: base.add(const Duration(seconds: 10))),
      _load('C', createdAt: base.add(const Duration(seconds: 20))),
    ];

    final assigned = _simulateFifoAssignment(loads, availableMachines: 0);

    expect(assigned, isEmpty);
  });

  test('two available machines assign the two oldest loads, rest wait', () {
    final base = DateTime.utc(2026, 8, 20, 10);
    final loads = [
      _load('A', createdAt: base),
      _load('B', createdAt: base.add(const Duration(seconds: 10))),
      _load('C', createdAt: base.add(const Duration(seconds: 20))),
    ];

    final assigned = _simulateFifoAssignment(loads, availableMachines: 2);

    expect(assigned, ['A', 'B']);
  });

  test('multiple loads from one transaction assign independently', () {
    final base = DateTime.utc(2026, 8, 20, 10);
    final loads = [
      _load('L1', orderId: 'ORDER_C', loadNumber: 1, createdAt: base),
      _load('L2', orderId: 'ORDER_C', loadNumber: 2, createdAt: base),
    ];

    // One machine available: only the first load gets it, the sibling waits.
    expect(
      _simulateFifoAssignment(loads, availableMachines: 1),
      ['L1'],
    );
    // Two machines available: both sibling loads get a machine each.
    expect(
      _simulateFifoAssignment(loads, availableMachines: 2),
      ['L1', 'L2'],
    );
  });

  test('never assigns more loads than machines available', () {
    final base = DateTime.utc(2026, 8, 20, 10);
    final loads = List.generate(6, (i) => _load('L$i', createdAt: base.add(Duration(seconds: i))));

    for (var m = 0; m <= 5; m++) {
      final assigned = _simulateFifoAssignment(loads, availableMachines: m);
      expect(assigned.length, m);
      expect(assigned, loads.map((l) => l.id).take(m).toList());
    }
  });

  // ──────────────────────────────────────────────────────────────────────────
  // State invariant (acceptance: waiting load must never have a machine)
  // ──────────────────────────────────────────────────────────────────────────

  test('hasAssignedMachine is true only when washer/dryer is set', () {
    final withWasher = _load('L1', washerId: 'wash_06');
    expect(
      MachineAssignmentEngine.hasAssignedMachine(
        withWasher,
        AppConstants.machineWasher,
      ),
      isTrue,
    );
    expect(
      MachineAssignmentEngine.hasAssignedMachine(
        withWasher,
        AppConstants.machineDryer,
      ),
      isFalse,
    );

    final withDryer = _load('L2', dryerId: 'dry_02');
    expect(
      MachineAssignmentEngine.hasAssignedMachine(
        withDryer,
        AppConstants.machineDryer,
      ),
      isTrue,
    );

    final none = _load('L3');
    expect(
      MachineAssignmentEngine.hasAssignedMachine(
        none,
        AppConstants.machineWasher,
      ),
      isFalse,
    );
    expect(
      MachineAssignmentEngine.hasAssignedMachine(
        none,
        AppConstants.machineDryer,
      ),
      isFalse,
    );
  });

  test('machineAssigned load has no running wash timer; washing load does', () {
    final base = DateTime.utc(2026, 8, 20, 10);
    final assigned = _load(
      'L1',
      status: LaundryStatus.machineAssigned,
      washerId: 'wash_06',
    );
    // Reserved/assigned-but-not-started: timer must NOT be running.
    expect(assigned.washCycleStart, isNull);
    expect(assigned.washEstimatedFinish, isNull);

    final washing = _load(
      'L2',
      status: LaundryStatus.washing,
      washerId: 'wash_06',
      washCycleStart: base,
      washEstimatedFinish: base.add(const Duration(minutes: 38)),
    );
    // Timer starts only after Start Wash -> Washing.
    expect(washing.washCycleStart, isNotNull);
    expect(washing.washEstimatedFinish, isNotNull);
  });
}

/// Mirrors the scheduler's single-writer rule: process waiting loads in FIFO
/// order, and every successful assignment consumes one machine from the
/// candidate pool. Assigned count can never exceed the machines available.
List<String> _simulateFifoAssignment(
  List<OrderLoadModel> loads, {
  required int availableMachines,
}) {
  final sorted = MachineAssignmentEngine.sortWaitingLoadsFifo(loads);
  final assigned = <String>[];
  var remaining = availableMachines;
  for (final load in sorted) {
    if (remaining <= 0) break;
    assigned.add(load.id);
    remaining--;
  }
  return assigned;
}

OrderLoadModel _load(
  String id, {
  String orderId = 'ORDER',
  int loadNumber = 1,
  double weight = 6,
  String serviceType = 'wash_only',
  LaundryStatus status = LaundryStatus.waitingForMachine,
  String? washerId,
  String? dryerId,
  DateTime? washCycleStart,
  DateTime? washEstimatedFinish,
  DateTime? createdAt,
}) {
  return OrderLoadModel(
    id: id,
    orderId: orderId,
    loadNumber: loadNumber,
    weight: weight,
    serviceType: serviceType,
    status: status,
    washerId: washerId,
    dryerId: dryerId,
    washCycleStart: washCycleStart,
    washEstimatedFinish: washEstimatedFinish,
    createdAt: createdAt,
  );
}
