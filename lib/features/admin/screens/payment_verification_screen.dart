import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../models/payment_model.dart';
import '../../../models/order_model.dart';
import '../../../providers/payment_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../services/transaction_proof_service.dart';

class PaymentVerificationScreen extends StatelessWidget {
  const PaymentVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Verification')),
      body: StreamBuilder(
        stream: context.read<PaymentProvider>().streamPendingPayments(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 56, color: Colors.red),
                  const SizedBox(height: 12),
                  const Text(
                    'Could not load pending payments',
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final payments = snapshot.data ?? [];

          if (payments.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.verified_user, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text('No pending payments', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 4),
                  Text(
                    'All payments have been verified',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: payments.length,
            itemBuilder: (context, index) {
              final payment = payments[index];
              final receiptUrl = payment.receiptImageUrl ?? '';
              final hasReceipt =
                  receiptUrl.isNotEmpty || payment.receiptProofId != null;
              final dateFormatted = DateFormat(
                'MMM dd, yyyy h:mm a',
              ).format(payment.createdAt);

              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.payment,
                              color: AppColors.warning,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FutureBuilder<OrderModel?>(
                                  future: context
                                      .read<OrderProvider>()
                                      .getOrderById(payment.orderId),
                                  builder: (context, snap) {
                                    final order = snap.data;
                                    return Text(
                                      order?.displayNumber ??
                                          'Transaction ${payment.orderId.substring(0, 8).toUpperCase()}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dateFormatted,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.warning.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.hourglass_empty,
                                  color: AppColors.warning,
                                  size: 14,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Pending',
                                  style: TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),

                      // Payment Details
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoTile(
                              'Payment Method',
                              payment.method,
                              Icons.account_balance_wallet,
                            ),
                          ),
                          Expanded(
                            child: _buildInfoTile(
                              'Amount',
                              CurrencyHelper.formatSimple(payment.amount),
                              Icons.monetization_on,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (payment.referenceNumber != null &&
                          payment.referenceNumber!.isNotEmpty)
                        _buildDetailRow(
                          'Reference No.',
                          payment.referenceNumber!,
                        ),
                      if (payment.userId.isNotEmpty)
                        FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(payment.userId)
                              .get(),
                          builder: (context, userSnap) {
                            final data = userSnap.data;
                            final name =
                                data != null ? (data['name'] ?? '') as String : '';
                            return _buildDetailRow(
                              'Customer',
                              name.isNotEmpty
                                  ? name
                                  : payment.userId.length > 12
                                      ? '...${payment.userId.substring(payment.userId.length - 12)}'
                                      : payment.userId,
                            );
                          },
                        ),

                      // Receipt Image Section
                      if (hasReceipt) ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Receipt Screenshot',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _showReceiptPreview(context, payment),
                          child: Container(
                            height: 160,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _ReceiptImage(payment: payment),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () => _showReceiptPreview(context, payment),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.zoom_in,
                                size: 14,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Tap to view full receipt',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: ElevatedButton.icon(
                                icon: const Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                label: const Text(
                                  'Approve',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () =>
                                    _confirmApprove(context, payment.id),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: ElevatedButton.icon(
                                icon: const Icon(
                                  Icons.cancel,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                label: const Text(
                                  'Reject',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.error,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onPressed: () =>
                                    _showRejectDialog(context, payment.id),
                              ),
                            ),
                          ),
                        ],
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

  Widget _buildInfoTile(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showReceiptPreview(BuildContext context, PaymentModel payment) {
    final referenceNumber = payment.referenceNumber ?? '';
    final amount = payment.amount;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF1565C0),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Payment Receipt',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Image
            ClipRRect(
              child: SizedBox(
                width: double.infinity,
                height: 300,
                child: InteractiveViewer(
                  child: _ReceiptImage(payment: payment),
                ),
              ),
            ),
            // Details
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildReceiptDetail('Reference No.', referenceNumber),
                  const SizedBox(height: 8),
                  _buildReceiptDetail(
                    'Amount',
                    CurrencyHelper.formatSimple(amount),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptDetail(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }

  void _confirmApprove(BuildContext context, String paymentId) {
    final screenContext = context;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text('Approve Payment'),
          ],
        ),
        content: const Text(
          'By approving this payment:\n'
          '- Payment status will be set to Verified\n'
          '- The transaction is accepted and the paid amount is recorded\n'
          '- A laundry worker will be automatically assigned\n'
          '- Processing starts once the verified weight is recorded\n'
          '- Any balance due after weight verification is collected at '
          'pickup/delivery\n'
          '\nProceed with approval?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final paymentProvider =
                  screenContext.read<PaymentProvider>();
              final authProvider = screenContext.read<AuthProvider>();
              Navigator.pop(context);

              final adminId = authProvider.user?.id ?? '';
              final success = await paymentProvider.verifyPayment(
                paymentId,
                adminId,
                approved: true,
              );

              if (!screenContext.mounted) return;
              ScaffoldMessenger.of(screenContext).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      Icon(
                        success ? Icons.check_circle : Icons.error,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        success
                            ? 'Payment approved! Machine assigned.'
                            : (paymentProvider.error ??
                                'Verification failed. Please try again.'),
                      ),
                    ],
                  ),
                  backgroundColor:
                      success ? Colors.green : AppColors.error,
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(BuildContext context, String paymentId) {
    final reasonController = TextEditingController();
    final screenContext = context;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.cancel, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text('Reject Payment'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Provide a reason for rejection:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'e.g. Amount does not match',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.red, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Common reasons:',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _buildReasonChip(context, reasonController, 'Amount mismatch'),
                _buildReasonChip(
                  context,
                  reasonController,
                  'Blurry screenshot',
                ),
                _buildReasonChip(
                  context,
                  reasonController,
                  'Invalid reference',
                ),
                _buildReasonChip(
                  context,
                  reasonController,
                  'Duplicate payment',
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please provide a reason for rejection'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
                return;
              }
              
              final paymentProvider = screenContext.read<PaymentProvider>();
              final authProvider = screenContext.read<AuthProvider>();
              Navigator.pop(context);
              
              final adminId = authProvider.user?.id ?? '';
              await paymentProvider.verifyPayment(
                paymentId,
                adminId,
                approved: false,
                rejectionReason: reason,
              );
              
              if (screenContext.mounted) {
                ScaffoldMessenger.of(screenContext).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.info, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Payment rejected'),
                      ],
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Reject', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonChip(
    BuildContext context,
    TextEditingController controller,
    String reason,
  ) {
    return ActionChip(
      label: Text(reason, style: const TextStyle(fontSize: 11)),
      onPressed: () {
        controller.text = reason;
      },
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// Renders a payment receipt, preferring the new Base64 proof stored in
/// `transaction_proofs`. Falls back to the legacy Firebase Storage URL.
class _ReceiptImage extends StatelessWidget {
  const _ReceiptImage({required this.payment});

  final PaymentModel payment;

  @override
  Widget build(BuildContext context) {
    final proofId = payment.receiptProofId;
    final receiptUrl = payment.receiptImageUrl ?? '';

    if (proofId != null && proofId.isNotEmpty) {
      return FutureBuilder<Uint8List?>(
        future: TransactionProofService().loadImageBytes(
          proofId: proofId,
          orderId: payment.orderId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Container(
              color: Colors.grey.shade100,
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return Container(
              color: Colors.grey.shade100,
              child: const Center(
                child: Text(
                  'Receipt unavailable',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            );
          }
          return Image.memory(bytes, fit: BoxFit.cover);
        },
      );
    }

    if (receiptUrl.isNotEmpty) {
      return Image.network(
        receiptUrl,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            color: Colors.grey.shade100,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey.shade100,
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image, color: Colors.grey, size: 32),
              SizedBox(height: 4),
              Text(
                'Failed to load image',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.grey.shade100,
      child: const Center(
        child: Text(
          'No receipt',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ),
    );
  }
}
