import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../models/order_model.dart';
import '../../providers/order_provider.dart';
import '../../providers/auth_provider.dart';
import '../constants/app_colors.dart';

/// Renders the cash-remittance action for an order whose cash was collected by
/// the current user:
///
/// - Cash + Verified + current user is the collector + not yet Remitted:
///   a "Remit Cash to Admin" button (with confirm dialog) that calls
///   [OrderProvider.remitCash].
/// - Already pending admin confirmation: a "Pending Admin Confirmation" banner.
/// - Anything else: nothing (empty box).
///
/// Shared by the Delivery Staff dashboard and the Delivery History screen.
class RemittanceAction extends StatelessWidget {
  const RemittanceAction({super.key, required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthProvider>().user?.id ?? '';
    final isCollector = order.pickupCollectedBy == currentUserId;
    final isCash = AppConfig.isCashMethod(order.paymentMethod);
    final remittanceStatus = order.remittanceStatus ?? '';
    final needsRemit = isCash &&
        order.paymentStatus == 'Verified' &&
        isCollector &&
        remittanceStatus != AppConfig.remittanceConfirmed;
    if (!needsRemit) return const SizedBox.shrink();

    if (remittanceStatus == AppConfig.remittancePending) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_top, size: 16, color: AppColors.warning),
            SizedBox(width: 6),
            Text(
              'Pending Admin Confirmation',
              style: TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.account_balance, size: 18),
        label: const Text('Remit Cash to Admin'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.warning,
          foregroundColor: Colors.white,
        ),
        onPressed: () => _confirmRemitCash(context),
      ),
    );
  }

  void _confirmRemitCash(BuildContext context) {
    final amount = order.totalAmount;
    showDialog(
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
          'Confirm you have physically handed over ₱${amount.toStringAsFixed(2)} cash to the admin?',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final staffId = ctx.read<AuthProvider>().user?.id ?? '';
              final success = await ctx.read<OrderProvider>().remitCash(
                    orderId: order.id,
                    staffId: staffId,
                  );
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Cash remitted! Awaiting admin confirmation.'
                          : 'Failed to remit cash.',
                    ),
                    backgroundColor: success ? AppColors.warning : AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('Confirm Remittance', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}