# Multiple Load Order Support Implementation

## Overview
Implement support for orders exceeding machine capacity (8kg per machine).

## Completed Steps

- [x] **1. Create `OrderLoadModel`** — New model for individual load records
- [x] **2. Create `OrderLoadEngine`** — Engine for splitting orders into loads and deriving parent status
- [x] **3. Add `currentLoadId` to `MachineModel`** — Track which load a machine is assigned to
- [x] **4. Add `numberOfLoads` & `loadIds` to `OrderModel`** — Parent order metadata
- [x] **5. Update `OrderProvider`**
  - `approveOrder()`: Creates load records after approval
  - `streamOrderLoads()` / `streamAllLoads()` / `getLoadsForOrder()` / `completeLoad()`
  - `completeLoad()`: Marks a load completed, re-derives parent order status from all loads
  - `_ensureOrderInDeliveryQueue()`: Inserts order into delivery queue when all loads ready
- [x] **6. Update `MachineProvider`**
  - `assignMachineToLoad()`: Per-load machine assignment
  - `scheduleOrderLoads()`: Schedules all loads of an order independently
  - `scheduleSingleLoad()`: Schedules one load
  - `_deriveParentOrderStatus()`: Re-derives parent order status from all loads
  - `completeMachineStep()`: load-aware with dryer handoff + `currentLoadId`
  - `startMachineStep()`: Load-aware cycle timing
  - `_addToLaundryQueue()`: Queue for waiting loads (by loadId)
  - `_scheduleVerifiedOrder()` → `scheduleOrderLoads()`: Per-load scheduling
  - `setMaintenance()`: Clears `currentLoadId`
- [x] **7. Update `WalkinTransactionScreen`** — Creates load records for walk-in orders
- [x] **8. Update `LaundryTaskScreen`** — Displays individual loads, per-load action buttons
- [x] **9. Update `StaffHomeScreen::LaundryTasksTab`** — Shows loads list instead of orders
- [x] **10. Update `OrderTrackingScreen`** — Shows individual load progress
- [x] **11. Update `OrderHistoryScreen`** — Shows loads per order
- [x] **12. Update `HomeScreen`** — Shows loads in active orders
- [x] **13. Update `MachineMonitorScreen`** — Uses `currentLoadId` for live timer
- [x] **14. Update `OrderStatusFlowEngine`** — Adds per-load status constants
- [x] **15. Update `AppConstants`** — Adds load flow constants
- [x] **16. Add `orderLoads` to `firebase_rules.txt`** — Firestore security rules
- [x] **17. Add `orderLoads` to `database_structure.md`** — Database documentation

## Fixes

- [x] **18. Fix Admin "Assign Staff" empty list** — `manage_orders_screen.dart`
  `_fetchStaffUsers()` queried `role == 'staff'`, but laundry staff are stored
  with role `'laundry_staff'` (see `role_model.dart`). Changed to
  `whereIn: ['staff', 'laundry_staff']` so all registered laundry staff appear.
- [x] **19. Laundry Task screen navigation** — Added a back button in the AppBar
  and a "Back to Dashboard" button in the completed/all-tasks-done state so
  staff can return to the main screen.

## Implementation Details

### Machine Capacity
- Each washing machine capacity = 8kg
- If customer laundry weight > 8kg: `numberOfLoads = ceil(totalWeight / 8)`
- Example: 20kg → Load 1=8kg, Load 2=8kg, Load 3=4kg

### `orderLoads` Collection
Each load document:
```json
{
  loadId: string,
  orderId: string,
  loadNumber: int,
  weight: double,
  serviceType: string,
  machineType: string,
  machineId: string,
  status: string,
  cycleStart: timestamp,
  estimatedFinish: timestamp
}
```

### Per-Load Status Flow
```
Waiting for Machine → Machine Assigned → Washing → Drying → Completed
```

### Parent Order Status
- Based on all load statuses
- "Ready for Pickup/Delivery" only when ALL loads are completed

