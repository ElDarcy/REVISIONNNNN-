import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../providers/delivery_provider.dart';
import '../../../engines/delivery_priority_engine.dart';

class DeliveryQueueScreen extends StatelessWidget {
  const DeliveryQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Queue')),
      body: StreamBuilder(
        stream: context.read<DeliveryProvider>().streamAllDeliveries(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final deliveries = snapshot.data ?? [];

          if (deliveries.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_shipping, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No deliveries yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          // Sort by priority
          final sorted = DeliveryPriorityEngine.sortByPriority(deliveries);

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final delivery = sorted[index];
              final priority = DeliveryPriorityEngine.getPriorityLabel(
                DeliveryPriorityEngine.calculatePriorityScore(delivery),
              );

              Color priorityColor;
              switch (priority) {
                case 'High':
                  priorityColor = AppColors.error;
                  break;
                case 'Medium':
                  priorityColor = AppColors.warning;
                  break;
                default:
                  priorityColor = AppColors.success;
              }

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: priorityColor.withValues(alpha: 0.1),
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        color: priorityColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(delivery.customerName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${delivery.distanceKm.toStringAsFixed(1)} km - ${delivery.customerAddress}',
                      ),
                      Text('Status: ${delivery.status}'),
                    ],
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: priorityColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      priority,
                      style: TextStyle(
                        color: priorityColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
