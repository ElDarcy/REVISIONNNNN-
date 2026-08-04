import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import 'delivery_tasks_screen.dart';
import 'delivery_history_screen.dart';
import '../../../models/delivery_queue_entry_model.dart';
import '../../../providers/delivery_provider.dart';

/// Delivery Staff home with bottom navigation.
///
/// Delivery Staff see ONLY delivery-related screens:
///   - Delivery Dashboard (summary)
///   - Delivery Tasks (Ready for Delivery / Out for Delivery)
///   - Delivery History (Completed)
///   - Profile
///
/// They do NOT see laundry processing tasks.
class DeliveryStaffHomeScreen extends StatefulWidget {
  const DeliveryStaffHomeScreen({super.key});

  @override
  State<DeliveryStaffHomeScreen> createState() =>
      _DeliveryStaffHomeScreenState();
}

class _DeliveryStaffHomeScreenState extends State<DeliveryStaffHomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final screens = [
      const _DeliveryDashboard(),
      const DeliveryTasksScreen(),
      const DeliveryHistoryScreen(),
      const _DeliveryProfileScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Delivery - ${user?.name ?? 'Staff'}'),
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
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
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

class _DeliveryDashboard extends StatelessWidget {
  const _DeliveryDashboard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DeliveryQueueEntry>>(
      stream: context.read<DeliveryProvider>().streamDeliveryQueue(),
      builder: (context, snapshot) {
        final entries = snapshot.data ?? [];
        final pending = entries
            .where((e) => e.status == 'Pending Delivery')
            .length;
        final out = entries.where((e) => e.status == 'Out for Delivery').length;
        final completed = entries.where((e) => e.status == 'Completed').length;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      'Pending Delivery',
                      pending.toString(),
                      AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statCard(
                      'Out for Delivery',
                      out.toString(),
                      AppColors.processingColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statCard(
                      'Completed',
                      completed.toString(),
                      AppColors.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Delivery Tasks',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.local_shipping),
                  ),
                  title: const Text('Delivery Tasks'),
                  subtitle: Text('$pending deliveries ready'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DeliveryTasksScreen(),
                    ),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.history)),
                  title: const Text('Delivery History'),
                  subtitle: Text('$completed completed deliveries'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DeliveryHistoryScreen(),
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

class _DeliveryProfileScreen extends StatelessWidget {
  const _DeliveryProfileScreen();

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
            subtitle: Text('Delivery Staff'),
          ),
        ),
      ],
    );
  }
}
