import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/machine_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../providers/service_provider.dart';
import '../../../models/machine_model.dart';
import '../../../models/service_model.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ServiceProvider>().loadServices();
      context.read<MachineProvider>().seedDefaultMachines();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;
    final serviceProvider = context.watch<ServiceProvider>();
    final services = serviceProvider.services;
    final isServicesLoading = serviceProvider.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text('Hello, ${user?.name ?? 'Customer'}!'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () => Navigator.pushNamed(context, '/customer/profile'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick Actions
            _buildQuickActions(),
            const SizedBox(height: 24),
            // Shop Capacity
            const Text(
              'Shop Capacity',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildCapacityView(),
            const SizedBox(height: 24),
            // Services
            const Text(
              'Our Services',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildServicesGrid(services, isServicesLoading: isServicesLoading),
            const SizedBox(height: 24),
            // Active Orders
            const Text(
              'Active Orders',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildActiveOrders(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        onTap: (index) {
          if (index == 1) {
            Navigator.pushNamed(context, '/customer/order-history');
          }
          if (index == 2) {
            Navigator.pushNamed(context, '/customer/profile');
          }
        },
      ),
    );
  }

  /// Capacity view shows ONLY aggregate totals (no machine IDs exposed).
  Widget _buildCapacityView() {
    return StreamBuilder<List<MachineModel>>(
      stream: context.read<MachineProvider>().streamMachines(),
      builder: (context, snapshot) {
        final machines = snapshot.data ?? [];
        final washers = machines
            .where((m) => m.type == AppConstants.machineWasher)
            .toList();
        final dryers = machines
            .where((m) => m.type == AppConstants.machineDryer)
            .toList();

        final washerAvailable = washers.where((m) => m.isAvailable).length;
        final washerInUse = washers.where((m) => m.isInUse).length;
        final dryerAvailable = dryers.where((m) => m.isAvailable).length;
        final dryerInUse = dryers.where((m) => m.isInUse).length;

        return Row(
          children: [
            Expanded(
              child: _capacityCard(
                title: 'Washing Machines',
                icon: Icons.wash,
                color: AppColors.processingColor,
                available: washerAvailable,
                inUse: washerInUse,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _capacityCard(
                title: 'Dryers',
                icon: Icons.air,
                color: Colors.deepPurple,
                available: dryerAvailable,
                inUse: dryerInUse,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _capacityCard({
    required String title,
    required IconData icon,
    required Color color,
    required int available,
    required int inUse,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '🟢 Available: $available',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              inUse > 0 ? '🔵 In Use: $inUse' : '🟣 In Use: $inUse',
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _buildActionCard(
            icon: Icons.add_circle_outline,
            label: 'New Order',
            color: AppColors.primary,
            onTap: () => Navigator.pushNamed(context, '/customer/create-order'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionCard(
            icon: Icons.track_changes,
            label: 'Track Order',
            color: AppColors.success,
            onTap: () =>
                Navigator.pushNamed(context, '/customer/order-history'),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 40, color: color),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServicesGrid(
    List<ServiceModel> services, {
    bool isServicesLoading = false,
  }) {
    // Get icon based on service name
    IconData getServiceIcon(String name) {
      if (name.toLowerCase().contains('wash')) return Icons.wash;
      if (name.toLowerCase().contains('dry')) return Icons.air;
      return Icons.local_laundry_service;
    }

    if (isServicesLoading && services.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show whatever services are currently loaded (even during loading,
    // use previously loaded data to prevent blank/loading flash)
    final displayServices = services;

    return Column(
      children: [
        if (displayServices.isEmpty && !isServicesLoading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No services available'),
            ),
          )
        else if (displayServices.isEmpty && isServicesLoading)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: displayServices.length,
            itemBuilder: (context, index) {
              final service = services[index];
              return Card(
                child: InkWell(
                  onTap: () =>
                      Navigator.pushNamed(context, '/customer/create-order'),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          getServiceIcon(service.name),
                          size: 32,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          service.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₱${service.pricePerKg.toStringAsFixed(0)}/cycle',
                          style: TextStyle(
                            color: AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Max ${service.maxKgPerCycle.toStringAsFixed(0)}kg/cycle',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildActiveOrders() {
    return StreamBuilder(
      stream: context.read<OrderProvider>().streamUserOrders(
        context.read<AuthProvider>().user?.id ?? '',
      ),
      builder: (context, snapshot) {
        // Initial load: show a spinner only while waiting for the first event.
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        // Stream error (e.g. lost connection / permission).
        if (snapshot.hasError) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Unable to load your orders. Please check your connection.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          );
        }

        final orders = snapshot.data ?? [];

        if (orders.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No Orders Yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "You haven't placed any orders yet.\nOnce you do, they'll appear here.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final activeOrders = orders.where((o) => !o.status.isFinished).toList();

        if (activeOrders.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No active orders',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          );
        }

        return Column(
          children: activeOrders.take(3).map((order) {
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.local_laundry_service,
                    color: AppColors.primary,
                  ),
                ),
                title: Text('Order #${order.id.substring(0, 6).toUpperCase()}'),
                subtitle: Text('Status: ${order.status.value}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pushNamed(
                  context,
                  '/customer/order-tracking',
                  arguments: {'orderId': order.id},
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
