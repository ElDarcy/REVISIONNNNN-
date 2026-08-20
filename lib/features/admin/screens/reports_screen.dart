import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../core/utils/date_helper.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          final orders = snapshot.data!.docs;

          final totalOrders = orders.length;
          final totalRevenue = orders.fold<double>(0.0, (sum, doc) {
            final amount = (doc['totalAmount'] as num?)?.toDouble() ?? 0.0;
            return sum + amount;
          });
          final completedOrders = orders.where((d) {
            return (d['status'] as String?) == 'Completed';
          }).length;
          final pendingOrders = orders.where((d) {
            return (d['status'] as String?) == 'Pending';
          }).length;
          final avgOrderValue = totalOrders > 0
              ? totalRevenue / totalOrders
              : 0.0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildReportCard(
                        'Total Revenue',
                        CurrencyHelper.formatSimple(totalRevenue),
                        Icons.trending_up,
                        AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildReportCard(
                        'Total Transactions',
                        totalOrders.toString(),
                        Icons.receipt,
                        AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildReportCard(
                        'Completed',
                        completedOrders.toString(),
                        Icons.check_circle,
                        AppColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildReportCard(
                        'Pending',
                        pendingOrders.toString(),
                        Icons.pending,
                        AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildReportCard(
                        'Avg Transaction',
                        CurrencyHelper.formatSimple(avgOrderValue),
                        Icons.analytics,
                        AppColors.processingColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Recent Transactions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...orders.take(10).map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final amount =
                      (data['totalAmount'] as num?)?.toDouble() ?? 0.0;
                  final status = data['status'] as String? ?? 'N/A';
                  final createdAt = data['createdAt'] as String?;
                  final txn = data['transactionNumber'] as String? ??
                      'Transaction #${doc.id.substring(0, 6).toUpperCase()}';

                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withValues(
                          alpha: 0.1,
                        ),
                        child: const Icon(
                          Icons.receipt,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        txn,
                      ),
                      subtitle: Text(
                        '$status | ${CurrencyHelper.formatSimple(amount)}',
                      ),
                      trailing: Text(
                        createdAt != null
                            ? DateHelper.formatDate(DateTime.parse(createdAt))
                            : '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildReportCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
