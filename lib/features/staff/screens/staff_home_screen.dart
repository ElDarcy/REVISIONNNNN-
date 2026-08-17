import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../providers/machine_provider.dart';
import '../../../engines/order_status_flow_engine.dart';
import '../../../models/order_model.dart';
import '../../../models/order_load_model.dart';
import '../../../models/laundry_status_model.dart';
import 'laundry_task_screen.dart';
import 'machine_monitor_screen.dart';

/// Laundry Staff home with bottom navigation.
///
/// Laundry Staff see ONLY laundry-related screens:
///   - Dashboard (summary only — no laundry operation buttons)
///   - Laundry Tasks (all laundry processing operations)
///   - Machine Monitor (read-only)
///   - Profile
class StaffHomeScreen extends StatefulWidget {
  const StaffHomeScreen({super.key});

  @override
  State<StaffHomeScreen> createState() => _StaffHomeScreenState();
}

class _StaffHomeScreenState extends State<StaffHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final screens = [
      const _LaundryDashboardTab(),
      const LaundryTasksTab(),
      const MachineMonitorScreen(),
      const _LaundryStaffProfileTab(),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('Laundry Staff - ${user?.name ?? ''}')),
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_laundry_service_outlined),
            selectedIcon: Icon(Icons.local_laundry_service),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.precision_manufacturing_outlined),
            selectedIcon: Icon(Icons.precision_manufacturing),
            label: 'Machines',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Full-screen Laundry Tasks list with a back button to the main screen.
///
/// Used when navigating from the Dashboard card so staff can always return
/// to the main StaffHomeScreen.
class LaundryTasksListScreen extends StatelessWidget {
  const LaundryTasksListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laundry Tasks'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to dashboard',
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: const _LaundryTasksListBody(),
    );
  }
}

/// A tab wrapper that embeds the LaundryTaskScreen list view.
class LaundryTasksTab extends StatelessWidget {
  const LaundryTasksTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LaundryTasksListBody();
  }
}

/// Shared list body used by both the Tasks tab and the full-screen list.
///
/// Displays PARENT ORDERS containing individual loads.
class _LaundryTasksListBody extends StatelessWidget {
  const _LaundryTasksListBody();

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.read<OrderProvider>();
    final machineProvider = context.read<MachineProvider>();
    final currentUser = context.watch<AuthProvider>().user;

    if (currentUser == null) return const SizedBox.shrink();

    return StreamBuilder<List<OrderModel>>(
      stream: orderProvider.streamStaffOrders(currentUser.id),
      builder: (context, ordersSnap) {
        return StreamBuilder<List<OrderLoadModel>>(
          stream: orderProvider.streamAllLoads(),
          builder: (context, loadsSnap) {
            if (ordersSnap.connectionState == ConnectionState.waiting ||
                loadsSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final myOrders = ordersSnap.data ?? [];
            final allLoads = loadsSnap.data ?? [];

            // Group all loads by orderId for easy lookup
            final Map<String, List<OrderLoadModel>> groupedLoads = {};
            for (final load in allLoads) {
              groupedLoads.putIfAbsent(load.orderId, () => []).add(load);
            }

            final activeOrders = <OrderModel>[];
            final completedOrders = <OrderModel>[];
            for (final order in myOrders) {
              final loads = groupedLoads[order.id] ?? const <OrderLoadModel>[];
              final allLoadsFinished =
                  loads.isNotEmpty && loads.every((load) => load.status.isFinished);
              final readyForFulfilment = order.status == LaundryStatus.readyForPickup ||
                  order.status == LaundryStatus.readyForDelivery ||
                  order.status == LaundryStatus.outForDelivery ||
                  order.status.isFinished;

              // Ready is the hand-off to the customer/delivery workflow, not
              // an active Laundry Staff task. A completed set of loads remains
              // visible once, in history.
              if (allLoadsFinished && readyForFulfilment) {
                completedOrders.add(order);
              } else if (!readyForFulfilment ||
                  loads.any((load) => !load.status.isFinished)) {
                activeOrders.add(order);
              }
            }

            if (activeOrders.isEmpty && completedOrders.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, size: 64, color: Colors.green),
                    const SizedBox(height: 16),
                    const Text(
                      'All laundry tasks completed!',
                      style: TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              );
            }

            activeOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            completedOrders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const Text('Active Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (activeOrders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('No active laundry tasks.'),
                  ),
                ...activeOrders.map((order) {
                  final loads = (groupedLoads[order.id] ?? [])
                      .where((load) => !load.status.isFinished)
                      .toList()
                    ..sort((a, b) => a.loadNumber.compareTo(b.loadNumber));
                  return _OrderGroupCard(order: order, loads: loads, machineProvider: machineProvider);
                }),
                const SizedBox(height: 12),
                const Text('Completed Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (completedOrders.isEmpty)
                  const Text('No completed laundry tasks.'),
                ...completedOrders.map((order) {
                  final loads = List<OrderLoadModel>.from(groupedLoads[order.id] ?? [])
                    ..sort((a, b) => a.loadNumber.compareTo(b.loadNumber));
                  return _OrderGroupCard(order: order, loads: loads, machineProvider: machineProvider);
                }),
              ],
            );
          },
        );
      },
    );
  }
}

class _OrderGroupCard extends StatelessWidget {
  final OrderModel order;
  final List<OrderLoadModel> loads;
  final MachineProvider machineProvider;

  const _OrderGroupCard({
    required this.order,
    required this.loads,
    required this.machineProvider,
  });

  String _customerLabel() {
    final name = order.customerName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return order.orderType == 'online' ? 'Online Customer' : 'Walk-in Customer';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Parent Order Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: const Icon(Icons.receipt, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.transactionNumber ?? 'Order #${order.id.substring(0, 6).toUpperCase()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Customer: ${_customerLabel()}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      Text(
                        'Service: ${order.serviceType ?? "Wash & Dry"}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${order.operationalWeight}kg',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      order.hasVerifiedActualWeight
                          ? 'Verified weight'
                          : 'Declared weight',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                    ),
                    Text(
                      '${order.numberOfLoads ?? loads.length} Load(s)',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (order.weightStatus == 'pending' || order.weightStatus == 'rejected')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    '/staff/weight-verification',
                    arguments: {'orderId': order.id},
                  ),
                  icon: const Icon(Icons.monitor_weight_outlined),
                  label: const Text('Verify Weight & Evidence'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          const Divider(height: 0),
          // Individual Loads List
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: loads.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final load = loads[index];
              return _LoadItemTile(
                load: load,
                machineProvider: machineProvider,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LoadItemTile extends StatefulWidget {
  final OrderLoadModel load;
  final MachineProvider machineProvider;

  const _LoadItemTile({required this.load, required this.machineProvider});

  @override
  State<_LoadItemTile> createState() => _LoadItemTileState();
}

class _LoadItemTileState extends State<_LoadItemTile> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(_LoadItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.load.status != oldWidget.load.status) {
      _startTimerIfNeeded();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimerIfNeeded() {
    final status = widget.load.status;
    if (status == LaundryStatus.washing || status == LaundryStatus.drying) {
      if (_timer == null || !_timer!.isActive) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final load = widget.load;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Load ${load.loadNumber}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${load.weight}kg)',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildMachineInfo(load),
                const SizedBox(height: 4),
                _buildStatusAndTimer(load),
              ],
            ),
          ),
          _buildActionButton(context, load),
        ],
      ),
    );
  }

  Widget _buildMachineInfo(OrderLoadModel load) {
    final washer = load.assignedWasherId;
    final dryer = load.assignedDryerId;
    
    if (washer == null && dryer == null) {
      return const Text('Machine: Not Assigned', style: TextStyle(fontSize: 12, color: Colors.grey));
    }
    
    final parts = <String>[];
    if (washer != null) parts.add('Washer: $washer');
    if (dryer != null) parts.add('Dryer: $dryer');
    
    return Text(
      parts.join(' · '),
      style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500),
    );
  }

  Widget _buildStatusAndTimer(OrderLoadModel load) {
    final statusValue = load.status.value;
    DateTime? finishTime;
    
    if (load.status == LaundryStatus.washing) {
      finishTime = load.washEstimatedFinish;
    } else if (load.status == LaundryStatus.drying) {
      finishTime = load.dryEstimatedFinish;
    }
    
    String timerText = "";
    if (finishTime != null) {
      final remaining = finishTime.difference(DateTime.now());
      if (remaining.isNegative) {
        timerText = " · Finishing...";
      } else {
        final m = remaining.inMinutes;
        final s = remaining.inSeconds % 60;
        timerText = " · ${m}m ${s}s";
      }
    }
    
    return Text(
      'Status: $statusValue$timerText',
      style: TextStyle(
        fontSize: 12, 
        color: _statusColor(statusValue),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, OrderLoadModel load) {
    final status = load.status;
    final serviceType = load.serviceType;
    
    // Logic mapping matching the instructions
    if (status == LaundryStatus.paymentVerified || 
        status == LaundryStatus.waitingForMachine || 
        status == LaundryStatus.waitingForDryer) {
      String label = "Waiting...";
      if (status == LaundryStatus.waitingForMachine) label = "Wait Washer";
      if (status == LaundryStatus.waitingForDryer) label = "Wait Dryer";
      
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      );
    }

    if (status == LaundryStatus.machineAssigned) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.processingColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          minimumSize: const Size(100, 32),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => _startStep(context, load, AppConstants.machineWasher),
        child: const Text('Start Wash', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }

    if (status == LaundryStatus.washing) {
      final needsDry = OrderStatusFlowEngine.needsDrying(serviceType);
      final nextStatus = needsDry
          ? OrderStatusFlowEngine.statusWaitingForDryer
          : OrderStatusFlowEngine.statusCompleted;
          
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          minimumSize: const Size(100, 32),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => _completeStep(context, load, AppConstants.machineWasher, nextStatus),
        child: const Text('Done Wash', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }

    if (status == LaundryStatus.dryerAssigned) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          minimumSize: const Size(100, 32),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => _startStep(context, load, AppConstants.machineDryer),
        child: const Text('Start Dry', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }

    if (status == LaundryStatus.drying) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          minimumSize: const Size(100, 32),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: () => _completeStep(context, load, AppConstants.machineDryer, OrderStatusFlowEngine.statusCompleted),
        child: const Text('Done Dry', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }

    return const SizedBox(width: 100);
  }

  Future<void> _startStep(BuildContext context, OrderLoadModel load, String type) async {
    final machineId = type == AppConstants.machineWasher ? load.assignedWasherId : load.assignedDryerId;
    if (machineId == null) return;
    
    final machineProvider = context.read<MachineProvider>();
    final success = await machineProvider.startMachineStep(
      orderId: load.orderId,
      machineId: machineId,
      machineType: type,
      loadId: load.id,
    );
    
    if (mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to start machine.')));
    }
  }

  Future<void> _completeStep(BuildContext context, OrderLoadModel load, String type, String next) async {
    final machineId = type == AppConstants.machineWasher ? load.assignedWasherId : load.assignedDryerId;
    final machineProvider = context.read<MachineProvider>();
    
    final success = await machineProvider.completeMachineStep(
      orderId: load.orderId,
      machineType: type,
      machineId: machineId ?? "",
      nextStatus: next,
      serviceType: load.serviceType,
      loadId: load.id,
    );
    
    if (mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to complete step.')));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Waiting for Machine':
      case 'Waiting for Dryer':
        return Colors.orange;
      case 'Machine Assigned':
      case 'Dryer Assigned':
        return AppColors.processingColor;
      case 'Washing':
      case 'Drying':
        return AppColors.accent;
      default:
        return Colors.grey;
    }
  }
}

/// Summary-only dashboard for laundry staff. Contains NO operation buttons.
class _LaundryDashboardTab extends StatelessWidget {
  const _LaundryDashboardTab();

  @override
  Widget build(BuildContext context) {
    final orderProvider = context.read<OrderProvider>();
    final currentUser = context.watch<AuthProvider>().user;

    if (currentUser == null) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<List<OrderModel>>(
      stream: orderProvider.streamStaffOrders(currentUser.id),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final orders = snapshot.data!;
        
        final processing = orders.where((o) => 
            !o.status.isFinished && 
            !o.status.isDelivering && 
            o.status != LaundryStatus.awaitingPickup &&
            o.status != LaundryStatus.pickupAssigned &&
            o.status != LaundryStatus.collected &&
            o.status != LaundryStatus.inTransit
        ).length;

        final ready = orders.where((o) => 
            o.status == LaundryStatus.readyForDelivery || 
            o.status == LaundryStatus.readyForPickup
        ).length;

        final completed = orders.where((o) => 
            o.status == LaundryStatus.completed || 
            o.status == LaundryStatus.delivered
        ).length;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      'Processing',
                      processing.toString(),
                      AppColors.processingColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statCard(
                      'Ready',
                      ready.toString(),
                      AppColors.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statCard(
                      'Completed',
                      completed.toString(),
                      AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Laundry Operations',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.local_laundry_service),
                  ),
                  title: const Text('Laundry Tasks'),
                  subtitle: Text('$processing active tasks assigned to you'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LaundryTasksListScreen(),
                    ),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.precision_manufacturing),
                  ),
                  title: const Text('Machine Monitor'),
                  subtitle: const Text('Live status of all 18 machines'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MachineMonitorScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String title, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _LaundryStaffProfileTab extends StatelessWidget {
  const _LaundryStaffProfileTab();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
        const SizedBox(height: 12),
        Center(
          child: Text(
            user?.name ?? '',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            user?.email ?? '',
            style: const TextStyle(color: Colors.grey),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.phone),
            title: const Text('Phone'),
            subtitle: Text(user?.phone ?? ''),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge),
            title: const Text('Role'),
            subtitle: Text('Laundry Staff'),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () async {
            await context.read<AuthProvider>().logout();
            if (context.mounted) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login',
                (route) => false,
              );
            }
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
          ),
          icon: const Icon(Icons.logout),
          label: const Text('Sign Out'),
        ),
      ],
    );
  }
}
