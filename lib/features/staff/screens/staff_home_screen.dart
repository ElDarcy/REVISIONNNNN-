import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../config/app_config.dart';
import '../../../core/utils/formatters.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../providers/machine_provider.dart';
import '../../../engines/order_status_flow_engine.dart';
import '../../../models/order_model.dart';
import '../../../models/order_load_model.dart';
import '../../../models/laundry_status_model.dart';

import 'machine_monitor_screen.dart';
import 'pickup_verification_screen.dart';

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
            final weightVerificationNeeded = <OrderModel>[];
            final awaitingGcashPayment = <OrderModel>[];
            for (final order in myOrders) {
              if (order.weightStatus == 'pending') {
                weightVerificationNeeded.add(order);
              }
              if (order.paymentMethod == 'GCash' &&
                  order.paymentStatus == 'Pending Verification' &&
                  order.weightStatus == 'verified' &&
                  !order.status.isFinished) {
                awaitingGcashPayment.add(order);
              }
              final isTerminal = order.status == LaundryStatus.readyForPickup ||
                  order.status == LaundryStatus.readyForDelivery ||
                  order.status == LaundryStatus.outForDelivery ||
                  order.status.isFinished;
              if (isTerminal) {
                completedOrders.add(order);
              } else {
                activeOrders.add(order);
              }
            }

            if (activeOrders.isEmpty && completedOrders.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle, size: 64, color: Colors.green),
                    SizedBox(height: 16),
                    Text(
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
                // BUG FIX: Prominent weight verification section at the top
                if (weightVerificationNeeded.isNotEmpty) ...[
                  Material(
                    type: MaterialType.transparency,
                    child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.warning,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.monitor_weight,
                              color: AppColors.warning,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'WEIGHT VERIFICATION NEEDED (${weightVerificationNeeded.length})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...weightVerificationNeeded.map((order) => Material(
                          type: MaterialType.transparency,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              order.displayNumber,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('${order.operationalWeight}kg · ${order.customerName ?? "Customer"}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.pushNamed(
                              context,
                              '/staff/weight-verification',
                              arguments: {'orderId': order.id},
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Orders weight-verified but held for GCash payment verification.
                if (awaitingGcashPayment.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'AWAITING GCASH PAYMENT VERIFICATION (${awaitingGcashPayment.length})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ...awaitingGcashPayment.map(
                          (order) => Text(
                            '${order.displayNumber} — ${order.customerName ?? "Customer"}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (activeOrders.isNotEmpty) ...[
                  const Text('Active Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...activeOrders.map((order) {
                    final loads = (groupedLoads[order.id] ?? [])
                        .where((load) => !load.status.isFinished)
                        .toList()
                      ..sort((a, b) => a.loadNumber.compareTo(b.loadNumber));
                    return _OrderGroupCard(order: order, loads: loads, machineProvider: machineProvider);
                  }),
                  const SizedBox(height: 12),
                ],
                if (completedOrders.isNotEmpty) ...[
                  const Text('Completed Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...completedOrders.map((order) {
                    final loads = List<OrderLoadModel>.from(groupedLoads[order.id] ?? [])
                      ..sort((a, b) => a.loadNumber.compareTo(b.loadNumber));
                    return _OrderGroupCard(order: order, loads: loads, machineProvider: machineProvider);
                  }),
                ],
                if (activeOrders.isEmpty && completedOrders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('No tasks assigned to you yet.', style: TextStyle(color: Colors.grey)),
                  ),
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
    if (name != null && name.isNotEmpty) return Formatters.toTitleCase(name);
    // BUG FIX: Never default online orders to "Walk-in Customer"
    if (order.orderType == 'walk_in') return 'Walk-in Customer';
    if (order.orderType == 'online') return 'Online Customer';
    return 'Customer';
  }

  void _confirmCashCollection(BuildContext context) {
    final amount = order.totalAmount;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.payments_outlined, color: AppColors.success, size: 28),
            SizedBox(width: 8),
            Text('Collect Cash'),
          ],
        ),
        content: Text(
          'Collect ₱${amount.toStringAsFixed(2)} cash from customer?',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final staffId = context.read<AuthProvider>().user?.id ?? '';
              final success = await context.read<OrderProvider>().collectCashPayment(
                orderId: order.id,
                staffId: staffId,
                amount: amount,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'Cash collected successfully!' : 'Failed to record cash collection.',
                    ),
                    backgroundColor: success ? AppColors.success : AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Confirm Collection', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDropOffCashCollection(BuildContext context) {
    final amount = order.totalAmount;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.payments_outlined, color: AppColors.success, size: 28),
            SizedBox(width: 8),
            Text('Collect Cash at Drop-off'),
          ],
        ),
        content: Text(
          'Collect ₱${amount.toStringAsFixed(2)} cash from the customer '
          'while their laundry is dropped off at the shop?',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final staffId = ctx.read<AuthProvider>().user?.id ?? '';
              final success =
                  await ctx.read<OrderProvider>().collectCashPayment(
                        orderId: order.id,
                        staffId: staffId,
                        amount: amount,
                      );
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Cash collected. Remember to remit it to the admin.'
                          : 'Failed to record cash collection.',
                    ),
                    backgroundColor: success
                        ? AppColors.success
                        : AppColors.error,
                  ),
                );
              }
              // Whoever collects the cash must be the one to remit it.
              if (success && ctx.mounted) {
                final remit = await showDialog<bool>(
                  context: ctx,
                  builder: (ctx2) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    title: const Row(
                      children: [
                        Icon(Icons.account_balance,
                            color: AppColors.warning, size: 28),
                        SizedBox(width: 8),
                        Text('Remit Cash'),
                      ],
                    ),
                    content: Text(
                      'Confirm you have physically handed over '
                      '₱${amount.toStringAsFixed(2)} cash to the admin?',
                      style: const TextStyle(fontSize: 15),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx2, false),
                        child: const Text('Later'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx2, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                        ),
                        child: const Text(
                          'Confirm Remittance',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                );
                if (remit == true && ctx.mounted) {
                  final staffId = ctx.read<AuthProvider>().user?.id ?? '';
                  await ctx.read<OrderProvider>().remitCash(
                        orderId: order.id,
                        staffId: staffId,
                      );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Confirm Collection', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

@override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthProvider>().user?.id ?? '';
    final isCollector = (order.pickupCollectedBy ?? order.cashCollectedBy) ==
        currentUserId;
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
                        order.displayNumber,
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
          if (order.weightStatus == 'pending')
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
          if (order.deliveryMethod != 'Pickup' &&
              AppConfig.isCashMethod(order.paymentMethod) &&
              order.paymentStatus == 'Pending Collection' &&
              order.remittanceStatus != 'Remitted')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmDropOffCashCollection(context),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Collect Cash at Drop-off'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          if (order.paymentMethod != 'GCash' &&
              order.paymentStatus == 'Pending Collection' &&
              (order.status == LaundryStatus.readyForPickup ||
               order.status == LaundryStatus.readyForDelivery ||
               order.status == LaundryStatus.outForDelivery))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmCashCollection(context),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Collect Cash'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          if (order.paymentMethod != 'GCash' &&
              order.paymentStatus == 'Verified' &&
              isCollector &&
              (order.remittanceStatus == null || order.remittanceStatus == ''))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmRemitCash(context),
                  icon: const Icon(Icons.account_balance, size: 18),
                  label: const Text('Remit Cash to Admin'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
          if (order.paymentMethod != 'GCash' &&
              order.paymentStatus == 'Verified' &&
              order.remittanceStatus == 'Pending Remittance')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.hourglass_top, size: 16, color: AppColors.warning),
                    SizedBox(width: 6),
                    Text(
                      'Pending Admin Confirmation',
                      style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 0),
          // Individual Loads List
          StreamBuilder<Map<String, int>>(
            stream: context.read<OrderProvider>().streamQueuePositions(),
            builder: (context, queueSnap) {
              final queuePositions = queueSnap.data ?? {};
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: loads.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final load = loads[index];
                  return _LoadItemTile(
                    load: load,
                    machineProvider: machineProvider,
                    machineHistory: order.machineHistory,
                    queuePosition: queuePositions[load.id],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  void _confirmRemitCash(BuildContext context) {
    final amount = order.totalAmount;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.account_balance, color: AppColors.warning, size: 28),
            SizedBox(width: 8),
            Text('Remit Cash'),
          ],
        ),
        content: Text(
          'Confirm you have physically handed over ₱${amount.toStringAsFixed(2)} cash to the admin?',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final staffId = ctx.read<AuthProvider>().user?.id ?? '';
              final success = await ctx.read<OrderProvider>().remitCash(
                orderId: order.id,
                staffId: staffId,
              );
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'Cash remitted! Awaiting admin confirmation.' : 'Failed to remit cash.',
                    ),
                    backgroundColor: success ? AppColors.warning : AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('Confirm Remittance', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

class _LoadItemTile extends StatefulWidget {
  final OrderLoadModel load;
  final MachineProvider machineProvider;
  final List<Map<String, dynamic>> machineHistory;
  final int? queuePosition;

  const _LoadItemTile({
    required this.load,
    required this.machineProvider,
    this.machineHistory = const [],
    this.queuePosition,
  });

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

    // Machine still assigned — show live IDs
    if (washer != null || dryer != null) {
      final parts = <String>[];
      if (washer != null) parts.add('Washer: ${_machineLabel(washer)}');
      if (dryer != null) parts.add('Dryer: ${_machineLabel(dryer)}');
      return Text(parts.join(' · '),
          style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500));
    }

    // Load is finished — look up from order's machineHistory
    if (load.status.isFinished && widget.machineHistory.isNotEmpty) {
      final washEntries = widget.machineHistory.where((h) => h['type'] == 'wash').toList();
      final dryEntries = widget.machineHistory.where((h) => h['type'] == 'dry').toList();
      final parts = <String>[];
      if (washEntries.isNotEmpty) {
        final idx = (load.loadNumber - 1).clamp(0, washEntries.length - 1);
        parts.add(washEntries[idx]['label']?.toString() ?? 'Washer');
      }
      if (dryEntries.isNotEmpty) {
        final dryIdx = (load.loadNumber - 1).clamp(0, dryEntries.length - 1);
        parts.add(dryEntries[dryIdx]['label']?.toString() ?? 'Dryer');
      }
      if (parts.isNotEmpty) {
        return Text(parts.join(' · '),
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500));
      }
    }

    return const Text('Machine: Not Assigned',
        style: TextStyle(fontSize: 12, color: Colors.grey));
  }

  /// Convert raw machine ID like 'wash_03' to 'Washer #3'.
  static String _machineLabel(String id) {
    final parts = id.split('_');
    if (parts.length == 2) {
      final type = parts[0] == 'wash' ? 'Washer' : 'Dryer';
      final num = int.tryParse(parts[1]);
      return num != null ? '$type #$num' : id;
    }
    return id;
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
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status: $statusValue$timerText',
          style: TextStyle(
            fontSize: 12, 
            color: _statusColor(statusValue),
            fontWeight: FontWeight.w600,
          ),
        ),
        if (widget.queuePosition != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Queue Position #${widget.queuePosition}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppColors.warning,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActionButton(BuildContext context, OrderLoadModel load) {
    final status = load.status;
    final serviceType = load.serviceType;
    
    // Waiting states are real: the load has NO machine until Machine Assigned.
    // The scheduler enforces this invariant (waiting load == no reserved
    // machine), so there are no safety-net buttons that pretend otherwise.
    if (status == LaundryStatus.waitingForMachine) {
      return _waitingLabel("Wait Washer");
    }
    if (status == LaundryStatus.waitingForDryer) {
      return _waitingLabel("Wait Dryer");
    }
    if (status == LaundryStatus.paymentVerified) {
      return _waitingLabel("Waiting...");
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

  Widget _waitingLabel(String label) {
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
            o.status == LaundryStatus.delivered ||
            o.status == LaundryStatus.pickedUp
        ).length;

        // Count orders needing weight verification (pending only)
        final needsWeightVerification = orders.where((o) =>
            o.weightStatus == 'pending'
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
              if (needsWeightVerification > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.warning, width: 2),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.monitor_weight, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Text(
                        '$needsWeightVerification transaction(s) need weight verification',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.warning,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.success,
                    child: Icon(Icons.qr_code_scanner, color: Colors.white),
                  ),
                  title: const Text('Verify Pickup'),
                  subtitle: const Text('Scan QR or enter code to release transaction'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PickupVerificationScreen(),
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
