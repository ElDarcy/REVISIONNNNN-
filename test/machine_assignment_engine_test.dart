import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_app/core/constants/app_constants.dart';
import 'package:laundry_app/engines/machine_assignment_engine.dart';
import 'package:laundry_app/models/machine_model.dart';

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
}
