import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../models/order_model.dart';
import '../../../providers/order_provider.dart';
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
      appBar: AppBar(
        title: Text('Laundry Staff - ${user?.name ?? ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
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
          ),
        ],
      ),
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

/// A tab wrapper that embeds the LaundryTaskScreen list view.
class LaundryTasksTab extends StatelessWidget {
  const LaundryTasksTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OrderModel>>(
      stream: context.read<OrderProvider>().streamAllOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snapshot.data ?? [];
        final active = orders.where((o) {
          return o.status.isProcessing ||
              o.status.value == 'Machine Assigned' ||
              o.status.value == 'Dryer Assigned' ||
              o.status.value == 'Ready for Pickup' ||
              o.status.value == 'Ready for Delivery';
        }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

        if (active.isEmpty) {
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

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: active.length,
          itemBuilder: (context, index) {
            final order = active[index];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: const Icon(Icons.receipt, color: AppColors.primary),
                ),
                title: Text('Order #${order.id.substring(0, 6).toUpperCase()}'),
                subtitle: Text('Status: ${order.status.value}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LaundryTaskScreen(orderId: order.id),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Summary-only dashboard for laundry staff. Contains NO operation buttons.
class _LaundryDashboardTab extends StatelessWidget {
  const _LaundryDashboardTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        final processing = docs.where((d) {
          final status = d['status'] as String?;
          return status == 'Payment Verified' ||
              status == 'Waiting for Machine' ||
              status == 'Machine Assigned' ||
              status == 'Washing' ||
              status == 'Waiting for Dryer' ||
              status == 'Dryer Assigned' ||
              status == 'Drying' ||
              status == 'Folding';
        }).length;
        final ready = docs.where((d) {
          final status = d['status'] as String?;
          return status == 'Ready for Delivery' || status == 'Ready for Pickup';
        }).length;
        final completed = docs.where((d) {
          final status = d['status'] as String?;
          return status == 'Completed';
        }).length;

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
                  subtitle: Text('$processing orders in progress'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LaundryTasksTab()),
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
      ],
    );
  }
}
