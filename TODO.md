# Machine Management, Maintenance Control, and Customer Availability Display

## Task 1: Constants & Status Definitions
- [x] **1.1** Add machine statuses: `busy`, `inactive`, `under_inspection` to `app_constants.dart`.
- [x] **1.2** Existing statuses (`reserved`, `washing`, `drying`) kept intact for the scheduler.

## Task 2: Models
- [x] **2.1** Updated `machine_model.dart`: added `isBusy`, `isInactive`, `isUnderInspection`; updated `isAvailable`/`isInUse` to only count `available` as available and reserved/busy/washing/drying as in-use.
- [x] **2.2** Created `maintenance_record_model.dart` (maintenanceId, machineId, machineType, reason, reportedBy, startedAt, expectedCompletionDate, completedAt, status, notes).
- [x] **2.3** Created `machine_issue_model.dart` (machineId, issueCategory, description, reportedBy, reportedAt).

## Task 3: Provider (RBAC + business logic)
- [x] **3.1** `updateMachineStatus(machineId, status)` — admin-only, active-load protection.
- [x] **3.2** `addMaintenanceRecord(...)` — creates record + sets machine to maintenance.
- [x] **3.3** `completeMaintenance(...)` — admin returns machine to available.
- [x] **3.4** `reportMachineIssue(...)` — staff submits issue; sets machine to under_inspection (after load completes if active).
- [x] **3.5** `streamMaintenanceRecords()` / `streamMachineIssues()`.
- [x] **3.6** Scheduler ignores busy/inactive/under_inspection (only available assignable).

## Task 4: Admin Machine Management Screen
- [x] **4.1** Created `admin_machine_management_screen.dart` — view all machines, change status, add maintenance records, complete maintenance.

## Task 5: Staff Machine Access
- [x] **5.1** Updated `machine_monitor_screen.dart` — added "Report Issue" (categories + description). Staff cannot set maintenance/inactive.

## Task 6: Customer Availability Display
- [x] **6.1** Customer capacity view in `home_screen.dart` — Available = available only; In-use = reserved/busy/washing/drying; excludes maintenance/inactive/under_inspection from available.

## Task 7: Routing & Integration
- [x] **7.1** Registered admin machine management route in `app.dart` + `app_routes.dart`.
- [x] **7.2** Added "Machine Management" action tile to `admin_dashboard_screen.dart`.

## Task 8: Verification
- [x] **8.1** `flutter analyze` — 33 issues (baseline, all info/warning level), no new errors.
