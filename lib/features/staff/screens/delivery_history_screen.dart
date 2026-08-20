import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/remittance_action.dart';
import '../../../models/delivery_queue_entry_model.dart';
import '../../../models/order_model.dart';
import '../../../providers/delivery_provider.dart';
import '../../../providers/order_provider.dart';

/// Delivery History screen for Delivery Staff.
///
/// Shows completed deliveries AND collected pickups (their laundry is at the
/// shop). Collected cash pickups still awaiting remittance show a "Remit Cash
/// to Admin" action right here, so a collector is never stuck.
class DeliveryHistoryScreen extends StatelessWidget {
  const DeliveryHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery History')),
      body: StreamBuilder<List<DeliveryQueueEntry>>(
        stream: context.read<DeliveryProvider>().streamDeliveryQueue(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data ?? [];
          final completed = entries
              .where(
                (e) =>
                    e.status == 'Completed' ||
                    (e.type == 'pickup' && e.status == 'Laundry Collected'),
              )
              .toList();

          if (completed.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No completed deliveries',
                    style: TextStyle(fontSize: 18),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: completed.length,
            itemBuilder: (context, index) {
              final entry = completed[index];
              final isCollectedPickup =
                  entry.type == 'pickup' && entry.status == 'Laundry Collected';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFFE8F5E9),
                            child: Icon(Icons.check_circle, color: Colors.green),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.transactionNumber ??
                                      'Delivery #${entry.orderId.substring(0, 6).toUpperCase()}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'Customer: ${entry.customerName ?? 'N/A'}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                Text(
                                  'Status: ${entry.status}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isCollectedPickup
                                        ? AppColors.success
                                        : Colors.grey.shade600,
                                  ),
                                ),
                                if (entry.completedAt != null)
                                  Text(
                                    'Completed: ${_formatDate(entry.completedAt!)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      FutureBuilder<OrderModel?>(
                        future: context
                            .read<OrderProvider>()
                            .getOrderById(entry.orderId),
                        builder: (context, orderSnap) {
                          final order = orderSnap.data;
                          if (order == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: RemittanceAction(order: order),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour > 12 ? local.hour - 12 : local.hour;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.month}/${local.day}/${local.year} $h:$m $ampm';
  }
}