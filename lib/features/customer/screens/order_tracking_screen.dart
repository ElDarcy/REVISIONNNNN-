import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../core/utils/date_helper.dart';
import '../../../providers/order_provider.dart';
import '../../../models/order_model.dart';
import '../../../engines/order_status_flow_engine.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;

  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  Timer? _timer;

  // Cache the order stream ONCE so the 1-second countdown Timer's setState()
  // does NOT re-subscribe to Firestore on every rebuild. This prevents the
  // repeated-subscription / infinite-loading / rebuild loop.
  late final Stream<OrderModel?> _orderStream;

  @override
  void initState() {
    super.initState();
    _orderStream = context.read<OrderProvider>().streamOrderById(
      widget.orderId,
    );
    // Refresh UI every second to update countdown timer
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatRemainingTime(Duration duration) {
    if (duration.isNegative) {
      return '0m 0s';
    }
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    return '${minutes}m ${seconds}s';
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes mins';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '$hours hr';
    return '${hours}h ${mins}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Track Order')),
      // Stream the order document in real time so the timer appears
      // immediately once the admin approves the order. Uses the cached
      // [_orderStream] so the 1-second countdown Timer re-render does not
      // re-subscribe to Firestore.
      body: StreamBuilder<OrderModel?>(
        stream: _orderStream,
        builder: (context, snapshot) {
          // Connection is waiting while the first document loads.
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Stream error (e.g. lost connection / permission).
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'Unable to load order. Please check your connection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          }

          final order = snapshot.data;
          if (order == null) {
            return const Center(child: Text('Order not found'));
          }

          final statusFlow = OrderStatusFlowEngine.getFullFlow(order);
          final currentIndex = statusFlow.indexOf(order.status.value);
          final progress = currentIndex >= 0
              ? (currentIndex + 1) / statusFlow.length
              : 0.0;

          // Calculate remaining time if approved
          Duration? remainingTime;
          if (order.estimatedFinishTime != null) {
            remainingTime = order.estimatedFinishTime!.difference(
              DateTime.now(),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Order Header
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Order #${order.id.substring(0, 6).toUpperCase()}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getStatusColor(order.status.value),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                order.status.value,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ordered: ${DateHelper.formatDateTime(order.createdAt)}',
                        ),
                        if (order.completedAt != null)
                          Text(
                            'Completed: ${DateHelper.formatDateTime(order.completedAt!)}',
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Waiting for Approval (no timer/countdown before approval)
                if (order.approvedAt == null) ...[
                  Card(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.hourglass_empty,
                                color: AppColors.warning,
                                size: 24,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Waiting for Approval',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.warning,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Your payment is being reviewed by the admin. '
                            'The laundry timer will start once your order is approved.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Estimated Finish Timer (only when approved)
                if (order.approvedAt != null &&
                    order.estimatedFinishTime != null &&
                    remainingTime != null) ...[
                  Card(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.05),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.access_time,
                                color: Color(0xFF1565C0),
                                size: 24,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Laundry Timer',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1565C0),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Remaining Time
                          Text(
                            _formatRemainingTime(remainingTime),
                            style: TextStyle(
                              fontSize: remainingTime.isNegative ? 24 : 36,
                              fontWeight: FontWeight.bold,
                              color: remainingTime.isNegative
                                  ? AppColors.success
                                  : const Color(0xFF1565C0),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            remainingTime.isNegative
                                ? 'Estimated completion time passed'
                                : 'Estimated time remaining',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          if (order.estimatedDuration != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Estimated Duration: ${_formatDuration(order.estimatedDuration!)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              Column(
                                children: [
                                  Text(
                                    'Started',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    DateHelper.formatTime(order.approvedAt!),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                children: [
                                  Text(
                                    'Est. Finish',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    DateHelper.formatTime(
                                      order.estimatedFinishTime!,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Progress Tracker
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Progress',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey.shade200,
                            color: AppColors.primary,
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...statusFlow.asMap().entries.map((entry) {
                          final index = entry.key;
                          final status = entry.value;
                          final isCompleted = index <= currentIndex;
                          final isCurrent = index == currentIndex;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isCompleted
                                        ? AppColors.primary
                                        : Colors.grey.shade300,
                                  ),
                                  child: isCompleted
                                      ? const Icon(
                                          Icons.check,
                                          size: 16,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  status,
                                  style: TextStyle(
                                    fontWeight: isCurrent
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isCompleted
                                        ? AppColors.primary
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Machine Assignment (only the customer's own order machines)
                if (order.assignedMachineId != null ||
                    order.machineHistory.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Machine',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (order.assignedMachineId != null &&
                              order.status.value == 'Washing')
                            _buildMachineRow(
                              icon: Icons.wash,
                              label: 'Wash Machine',
                              number: order.assignedMachineNumber,
                              color: AppColors.processingColor,
                            ),
                          if (order.assignedMachineId != null &&
                              order.status.value == 'Drying')
                            _buildMachineRow(
                              icon: Icons.air,
                              label: 'Dryer',
                              number: order.assignedMachineNumber,
                              color: Colors.deepPurple,
                            ),
                          if (order.machineHistory.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Machines Used',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            ...order.machineHistory.map((h) {
                              final label = (h['label'] as String?) ?? '';
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 2,
                                ),
                                child: Text(
                                  '• $label',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Order Details
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Order Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow('Weight', '${order.weight} kg'),
                        _buildDetailRow(
                          'Delivery Method',
                          order.deliveryMethod,
                        ),
                        if (order.deliveryFee > 0)
                          _buildDetailRow(
                            'Delivery Fee',
                            CurrencyHelper.formatWhole(order.deliveryFee),
                          ),
                        _buildDetailRow('Payment', order.paymentMethod),
                        _buildDetailRow('Payment Status', order.paymentStatus),
                        if (order.distanceKm != null)
                          _buildDetailRow(
                            'Distance',
                            '${order.distanceKm!.toStringAsFixed(1)} km',
                          ),
                        const Divider(),
                        _buildDetailRow(
                          'Total',
                          CurrencyHelper.formatSimple(order.totalAmount),
                          isBold: true,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (order.assignedTo != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.person,
                        color: AppColors.primary,
                      ),
                      title: const Text('Assigned Staff'),
                      subtitle: Text(
                        'ID: ${_formatId(order.assignedTo)}',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatId(String? id) {
    if (id == null || id.isEmpty) return 'N/A';
    return id.length > 8 ? id.substring(0, 8) : id;
  }

  Widget _buildMachineRow({
    required IconData icon,
    required String label,
    required int? number,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            '$label #$number',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending':
      case 'Pending Payment':
      case 'Payment Pending Verification':
        return AppColors.warning;
      case 'Payment Verified':
      case 'Order Received':
        return AppColors.processingColor;
      case 'Waiting for Machine':
      case 'Waiting for Dryer':
        return Colors.orange;
      case 'Washing':
      case 'Drying':
      case 'Folding':
        return AppColors.accent;
      case 'Ready for Delivery':
      case 'Ready for Pickup':
      case 'Out for Delivery':
        return Colors.orange;
      case 'Delivered':
      case 'Completed':
        return AppColors.success;
      case 'Cancelled':
        return AppColors.error;
      default:
        return Colors.grey;
    }
  }
}
