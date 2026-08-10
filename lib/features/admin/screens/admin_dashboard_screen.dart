import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: Text('Admin - ${user?.name ?? 'Dashboard'}'),
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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          final totalOrders = docs.length;
          final pendingPayments = docs.where((d) {
            final ps = d['paymentStatus'] as String?;
            return ps == 'Pending Verification';
          }).length;
          final processing = docs.where((d) {
            final status = d['status'] as String?;
            return status == 'Order Received' ||
                status == 'Payment Pending Verification' ||
                status == 'Payment Verified' ||
                status == 'Waiting for Machine' ||
                status == 'Washing' ||
                status == 'Waiting for Dryer' ||
                status == 'Drying' ||
                status == 'Folding';
          }).length;
          final completed = docs.where((d) {
            final status = d['status'] as String?;
            return status == 'Completed';
          }).length;
          final revenue = docs.fold<double>(0.0, (sum, d) {
            final amount = (d['totalAmount'] as num?)?.toDouble() ?? 0;
            return sum + amount;
          });

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: [
                    _buildStatCard(
                      'Total Orders',
                      totalOrders.toString(),
                      Icons.receipt,
                      AppColors.primary,
                    ),
                    _buildStatCard(
                      'Pending Payments',
                      pendingPayments.toString(),
                      Icons.payment,
                      AppColors.warning,
                    ),
                    _buildStatCard(
                      'Processing',
                      processing.toString(),
                      Icons.local_laundry_service,
                      AppColors.processingColor,
                    ),
                    _buildStatCard(
                      'Completed',
                      completed.toString(),
                      Icons.check_circle,
                      AppColors.success,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.trending_up,
                          size: 40,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Revenue',
                              style: TextStyle(color: Colors.grey),
                            ),
                            Text(
                              '₱${revenue.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Quick Actions',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildActionTile(
                  context,
                  Icons.receipt_long,
                  'Manage Orders',
                  '/admin/orders',
                ),
                _buildActionTile(
                  context,
                  Icons.verified_user,
                  'Verify Payments',
                  '/admin/payments',
                ),
                _buildActionTile(
                  context,
                  Icons.add_shopping_cart,
                  'Walk-in Transaction',
                  '/admin/walkin',
                ),
                _buildActionTile(
                  context,
                  Icons.bar_chart,
                  'Reports',
                  '/admin/reports',
                ),
                _buildActionTile(
                  context,
                  Icons.analytics_outlined,
                  'Machine Analytics',
                  '/admin/machine-analytics',
                ),
                _buildActionTile(
                  context,
                  Icons.precision_manufacturing,
                  'Machine Management',
                  '/admin/machine-management',
                ),
                _buildActionTile(
                  context,
                  Icons.soap,
                  'Soap Inventory',
                  '/admin/soaps',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
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

  Widget _buildActionTile(
    BuildContext context,
    IconData icon,
    String title,
    String route,
  ) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          child: Icon(icon, color: AppColors.primary),
        ),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pushNamed(context, route),
      ),
    );
  }
}
