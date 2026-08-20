import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../config/app_config.dart';
import '../../../models/delivery_queue_entry_model.dart';
import '../../../providers/delivery_provider.dart';
import '../../../providers/order_provider.dart';
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
          final tasks = entries.where((e) {
            if (e.type == 'pickup') {
              return e.status == 'Pending Pickup' || e.status == 'Pickup Assigned';
            }
            return e.status == 'Pending Delivery' ||
                e.status == 'Out for Delivery';
          }).toList();

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
                    'New pickup and delivery tasks will appear here',
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
    final isPickup = entry.type == 'pickup';
    final isOut = !isPickup && entry.status == 'Out for Delivery';
    final started = isPickup && entry.status == 'Pickup Assigned';
    final statusColor = started || isOut
        ? AppColors.processingColor
        : AppColors.warning;

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
                  child: Icon(
                    isPickup ? Icons.inventory_2_outlined : Icons.local_shipping,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<String>(
                        future: _getDisplayNumber(context),
                        builder: (context, snap) {
                          return Text(
                            snap.data ?? 'Transaction ${entry.orderId.substring(0, 6).toUpperCase()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          );
                        },
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
                    onPressed: entry.latitude == 0 && entry.longitude == 0
                        ? null
                        : () => NavigationService.openNavigation(
                            latitude: entry.latitude,
                            longitude: entry.longitude,
                            label: entry.customerName,
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: isPickup
                      ? (started
                          ? ElevatedButton.icon(
                              icon: const Icon(Icons.done_all, size: 18),
                              label: const Text('Collected'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.success,
                              ),
                              onPressed: () => _completePickup(context),
                            )
                          : ElevatedButton.icon(
                              icon: const Icon(Icons.play_arrow, size: 18),
                              label: const Text('Start Pickup'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.processingColor,
                              ),
                              onPressed: () => _startPickup(context),
                            ))
                      : (isOut
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
                            )),
                ),
              ],
            ),
            if (isOut)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Collect Balance'),
                    onPressed: () => _collectBalance(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<String> _getDisplayNumber(BuildContext context) async {
    // The queue entry carries the LT-YYYY-NNNN number when available, so the
    // title never depends on a network lookup (no random-id flash).
    if (entry.transactionNumber != null && entry.transactionNumber!.isNotEmpty) {
      return entry.transactionNumber!;
    }
    try {
      final order = await context.read<OrderProvider>().getOrderById(entry.orderId);
      return order?.displayNumber ?? 'Transaction ${entry.orderId.substring(0, 6).toUpperCase()}';
    } catch (_) {
      return 'Transaction ${entry.orderId.substring(0, 6).toUpperCase()}';
    }
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

  Future<void> _collectBalance(BuildContext context) async {
    final orderProvider = context.read<OrderProvider>();
    final staffId = context.read<AuthProvider>().user?.id ?? '';
    final order = await orderProvider.getOrderById(entry.orderId);
    if (!context.mounted) return;
    if (order == null) return;

    if (order.outstandingBalance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No outstanding balance for this transaction.')),
      );
      return;
    }

    final amount = order.outstandingBalance;
    var method = 'Cash';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Row(
              children: [
                Icon(Icons.payments_outlined, color: AppColors.warning, size: 28),
                SizedBox(width: 8),
                Text('Collect Balance'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Balance Due: ₱${amount.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Collect this remaining balance from the customer before completing the delivery.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Cash'),
                      selected: method == 'Cash',
                      onSelected: (_) => setDialogState(() => method = 'Cash'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('GCash'),
                      selected: method == 'GCash',
                      onSelected: (_) => setDialogState(() => method = 'GCash'),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                child: const Text('Confirm Collection', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;
    final success = await orderProvider.collectBalance(
      orderId: entry.orderId,
      staffId: staffId,
      amount: amount,
      method: method,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Balance collected.' : 'Failed to collect balance.',
          ),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  Future<void> _startPickup(BuildContext context) async {
    final staffId = context.read<AuthProvider>().user?.id ?? '';
    final success = await context.read<OrderProvider>().startPickup(
      orderId: entry.orderId,
      staffId: staffId,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Pickup started. Collect the laundry at the location.' : 'Failed to start pickup.',
          ),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  Future<void> _completePickup(BuildContext context) async {
    final orderProvider = context.read<OrderProvider>();
    final staffId = context.read<AuthProvider>().user?.id ?? '';
    final order = await orderProvider.getOrderById(entry.orderId);
    if (!context.mounted) return;
    if (order == null) return;

    var cashAmount = 0.0;
    var isCash = false;
    if (AppConfig.isCashMethod(order.paymentMethod) &&
        order.paymentStatus == 'Pending Collection') {
      isCash = true;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.payments_outlined, color: AppColors.success, size: 28),
              SizedBox(width: 8),
              Text('Collect Cash on Pickup'),
            ],
          ),
          content: Text(
            'Collect ₱${order.totalAmount.toStringAsFixed(2)} cash from the customer before marking the laundry as collected?',
            style: const TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              child: const Text('Confirm Collection', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      cashAmount = order.totalAmount;
    }

    final success = await orderProvider.completePickup(
      orderId: entry.orderId,
      staffId: staffId,
      cashAmount: cashAmount,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (isCash
                  ? 'Laundry collected. Remember to remit the cash to admin.'
                  : 'Laundry collected. Proceeding to the shop.')
              : 'Failed to record pickup.',
        ),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );

    // Cash collected at pickup must be handed to the admin before the laundry
    // leg can start (strict cash handover gate).
    if (success && isCash) {
      final remit = await showDialog<bool>(
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
            'Confirm you have physically handed over ₱${cashAmount.toStringAsFixed(2)} cash to the admin?',
            style: const TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
              child: const Text('Confirm Remittance', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (remit == true) {
        await orderProvider.remitCash(
          orderId: entry.orderId,
          staffId: staffId,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cash remitted. Awaiting admin confirmation.'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
      }
    }
  }

  Future<void> _completeDelivery(BuildContext context) async {
    // Check if this is a cash order that needs collection confirmation
    final orderProvider = context.read<OrderProvider>();
    final order = await orderProvider.getOrderById(entry.orderId);

    if (context.mounted && order != null &&
        AppConfig.isCashMethod(order.paymentMethod) &&
        order.paymentStatus == 'Pending Collection') {
      final confirmed = await showDialog<bool>(
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
            'Collect ₱${order.totalAmount.toStringAsFixed(2)} cash from customer?',
            style: const TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              child: const Text('Confirm Collection', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        final staffId = context.read<AuthProvider>().user?.id ?? '';
        await orderProvider.collectCashPayment(
          orderId: entry.orderId,
          staffId: staffId,
          amount: order.totalAmount,
        );
        // After collection, prompt to remit cash to admin
        if (context.mounted) {
          final remit = await showDialog<bool>(
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
                'Confirm you have physically handed over ₱${order.totalAmount.toStringAsFixed(2)} cash to the admin?',
                style: const TextStyle(fontSize: 15),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Skip'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
                  child: const Text('Confirm Remittance', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
          if (remit == true) {
            await orderProvider.remitCash(
              orderId: entry.orderId,
              staffId: staffId,
            );
          }
        }
      }
    }

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
