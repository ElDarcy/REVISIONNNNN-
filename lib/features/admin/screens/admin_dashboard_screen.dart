import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/soap_provider.dart';
import '../../../models/soap_model.dart';

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
                _buildLowStockAlert(context),
                const SizedBox(height: 24),
                const Text(
                  'Quick Actions',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildActionTile(
                  context,
                  Icons.receipt_long,
                  'Manage Laundry Transactions',
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
                _buildActionTile(
                  context,
                  Icons.tune,
                  'Business Configuration',
                  '/admin/business-configuration',
                ),
                _buildActionTile(context, Icons.workspace_premium, 'Verify Membership Payments', '/admin/membership-verification'),
                _buildActionTile(context, Icons.sell, 'Promotion Management', '/admin/promotions'),
                _buildActionTile(context, Icons.stars, 'Loyalty Reward Management', '/admin/loyalty-rewards'),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLowStockAlert(BuildContext context) {
    return StreamBuilder<List<SoapModel>>(
      stream: context.read<SoapProvider>().streamSoaps(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        
        final lowStockItems = snapshot.data!.where((s) => s.isLowStock || s.isOutOfStock).toList();
        if (lowStockItems.isEmpty) return const SizedBox.shrink();

        final outOfStockCount = lowStockItems.where((s) => s.isOutOfStock).length;
        final lowStockCount = lowStockItems.where((s) => s.isLowStock).length;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.red.shade200),
          ),
          color: Colors.red.shade50,
          child: InkWell(
            onTap: () => Navigator.pushNamed(context, '/admin/soaps'),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'INVENTORY ALERT',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.red.shade800,
                            letterSpacing: 1.2,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.red.shade300),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (outOfStockCount > 0)
                    Text(
                      '⚠ $outOfStockCount product(s) OUT OF STOCK',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 14),
                    ),
                  if (lowStockCount > 0)
                    Padding(
                      padding: EdgeInsets.only(top: outOfStockCount > 0 ? 4 : 0),
                      child: Text(
                        '⚠ $lowStockCount product(s) running low (< ${SoapModel.lowStockThreshold} units)',
                        style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black87, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: lowStockItems.take(5).map((soap) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: soap.isOutOfStock ? Colors.red.shade100 : Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${soap.name}: ${soap.stockQuantity}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: soap.isOutOfStock ? Colors.red.shade900 : Colors.orange.shade900,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (lowStockItems.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'and ${lowStockItems.length - 5} more...',
                        style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.red.shade700),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
