import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/delivery_queue_entry_model.dart';
import '../../../providers/delivery_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/navigation_service.dart';

/// Delivery Tasks screen for Delivery Staff.
///
/// Displays orders with status 'Ready for Delivery' and 'Out for Delivery'.
/// Delivery staff can:
///   - Open Google Maps navigation to the customer's location
///   - Start Delivery    (status -> Out for Delivery)
///   - Complete Delivery (status -> Completed)
class DeliveryTasksScreen extends StatelessWidget {
  const DeliveryTasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Tasks')),
      body: StreamBuilder<List<DeliveryQueueEntry>>(
        stream: context.read<DeliveryProvider>().streamDeliveryQueue(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data ?? [];
          final tasks = entries
              .where(
                (e) =>
                    e.status == 'Pending Delivery' ||
                    e.status == 'Out for Delivery',
              )
              .toList();

          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_shipping, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No delivery tasks', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 4),
                  Text(
                    'New deliveries will appear here',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final entry = tasks[index];
              return _DeliveryTaskCard(entry: entry);
            },
          );
        },
      ),
    );
  }
}

class _DeliveryTaskCard extends StatelessWidget {
  final DeliveryQueueEntry entry;

  const _DeliveryTaskCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isOut = entry.status == 'Out for Delivery';
    final statusColor = isOut ? AppColors.processingColor : AppColors.warning;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.1),
                  child: Icon(Icons.local_shipping, color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Delivery #${entry.orderId.substring(0, 6).toUpperCase()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Customer: ${entry.customerName ?? 'N/A'}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    entry.status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            // Address
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 18,
                  color: Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.address ?? 'No address provided',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Distance & ETA
            Row(
              children: [
                const Icon(Icons.straighten, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text('${entry.distanceKm.toStringAsFixed(1)} km'),
                const SizedBox(width: 16),
                const Icon(Icons.schedule, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text('ETA: ${entry.etaMinutes} mins'),
              ],
            ),
            const SizedBox(height: 16),
            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.navigation, size: 18),
                    label: const Text('Navigate'),
                    onPressed: () => NavigationService.openNavigation(
                      latitude: entry.latitude,
                      longitude: entry.longitude,
                      label: entry.customerName,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: isOut
                      ? ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: const Text('Complete Delivery'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                          ),
                          onPressed: () => _completeDelivery(context),
                        )
                      : ElevatedButton.icon(
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const Text('Start Delivery'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.processingColor,
                          ),
                          onPressed: () => _startDelivery(context),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startDelivery(BuildContext context) async {
    final staffId = context.read<AuthProvider>().user?.id ?? '';
    final success = await context.read<DeliveryProvider>().startDelivery(
      entry.orderId,
      staffId,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Delivery started.' : 'Failed to start delivery.',
          ),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  Future<void> _completeDelivery(BuildContext context) async {
    final success = await context.read<DeliveryProvider>().completeDelivery(
      entry.orderId,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Delivery completed!' : 'Failed to complete delivery.',
          ),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }
}
