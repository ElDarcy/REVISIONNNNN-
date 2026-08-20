import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../core/utils/date_helper.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/staff_name_widget.dart';
import '../../../providers/order_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/pickup_service.dart';
import '../../../services/transaction_proof_service.dart';
import '../../../models/order_model.dart';
import '../../../models/order_load_model.dart';
import '../../../models/laundry_status_model.dart';
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
      appBar: AppBar(title: const Text('Track Transaction')),
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
                      'Unable to load transaction. Please check your connection.',
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
            return const Center(child: Text('Transaction not found'));
          }

          final statusFlow = OrderStatusFlowEngine.getFullFlow(order);
          final currentIndex = statusFlow.indexOf(order.status.value);
          final progress = currentIndex >= 0
              ? (currentIndex + 1) / statusFlow.length
              : 0.0;

          // Calculate remaining time once processing has started
          // (uses canonical estimatedFinishTime).
          Duration? remainingTime;
          if (order.estimatedFinishTime != null) {
            remainingTime = order.estimatedFinishTime!.difference(
              DateTime.now(),
            );
          }

          // "Waiting to Start" shows while processing has not begun yet
          // (payment verification and/or weight recording still in progress).
          final awaitingStart = order.processingStartedAt == null &&
              (order.status == LaundryStatus.pending ||
               order.status == LaundryStatus.paymentPendingVerification);

          final isCancelled = order.status == LaundryStatus.cancelled;
          final canCancel = OrderStatusFlowEngine.canCustomerCancel(order);

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
                              'Transaction ${order.displayNumber}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            StatusBadge(
                              status: order.status.value,
                              isCustomerFacing: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Created: ${DateHelper.formatDateTime(order.createdAt)}',
                        ),
                        if (order.completedAt != null)
                          Text(
                            'Completed: ${DateHelper.formatDateTime(order.completedAt!)}',
                          ),
                        if (order.deliveryMethod == 'Pickup' &&
                            order.pickupStatus != null &&
                            order.pickupStatus != 'Laundry Collected')
                          Text(
                            'Staff pickup: ${order.pickupStatus}',
                            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Cancelled — replaces the progress UI for cancelled orders
                if (isCancelled) ...[
                  Card(
                    color: AppColors.error.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.cancel,
                            color: AppColors.error,
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Transaction Cancelled',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            order.cancellationReason != null &&
                                    order.cancellationReason!.isNotEmpty
                                ? 'Reason: ${order.cancellationReason}'
                                : 'This transaction has been cancelled.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          if (order.pendingRefund > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Refund due: ${CurrencyHelper.formatSimple(order.pendingRefund)} — the shop will return this to you.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.info,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Waiting to Start — shown only while processing has not begun
                if (awaitingStart) ...[
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
                                'Waiting to Start',
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
                            'Your transaction has been accepted. Your payment '
                            'is being verified and your laundry\u2019s weight is '
                            'being recorded. The laundry timer will start once '
                            'processing begins.',
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

                // Estimated Finish Timer (only once processing has started)
                if (order.processingStartedAt != null &&
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
                                      DateHelper.formatTime(
                                        order.processingStartedAt!,
                                      ),
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

                // Cancel Transaction — only before processing starts
                if (canCancel) ...[
                  Card(
                    color: AppColors.error.withValues(alpha: 0.05),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Need to cancel?',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'You can cancel while your laundry has not started processing.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _confirmCancel(context, order),
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Cancel Transaction'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.error,
                              side: const BorderSide(color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Progress Tracker
                if (!isCancelled) ...[
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
                ],

                // Per-Load Status — shows each load independently with queue position
                if (order.processingStartedAt != null) ...[
                  StreamBuilder<List<OrderLoadModel>>(
                    stream: context.read<OrderProvider>().streamOrderLoads(order.id),
                    builder: (context, loadsSnap) {
                      final loads = loadsSnap.data ?? [];
                      if (loads.isEmpty) return const SizedBox.shrink();
                      return StreamBuilder<Map<String, int>>(
                        stream: context.read<OrderProvider>().streamQueuePositions(),
                        builder: (context, queueSnap) {
                          final queuePositions = queueSnap.data ?? {};
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Loads (${loads.length})',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ...loads.map((load) {
                                    final queuePos = queuePositions[load.id];
                                    final isActive = !load.status.isFinished;
                                    final statusLabel = _loadStatusLabel(load);
                                    final statusColor = _loadStatusColor(load);
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: statusColor.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: statusColor.withValues(alpha: 0.2),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '${load.loadNumber}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: statusColor,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Load ${load.loadNumber} — ${load.weight.toStringAsFixed(1)} kg',
                                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  statusLabel,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: statusColor,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (queuePos != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppColors.warning.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                'Queue #$queuePos',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.warning,
                                                ),
                                              ),
                                            ),
                                          if (load.currentMachineId != null && isActive)
                                            Container(
                                              margin: const EdgeInsets.only(left: 6),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                load.currentMachineId!,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Fulfillment Choice — BUG FIX: Customer explicitly chooses pickup or delivery
                if (order.status == LaundryStatus.readyForPickup &&
                    !order.hasFulfillmentChoice) ...[
                  Card(
                    color: AppColors.success.withValues(alpha: 0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.success,
                            size: 40,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Your laundry is ready!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'How would you like to receive it?',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _chooseFulfillment(
                                    context,
                                    order.id,
                                    'Personal Pickup',
                                  ),
                                  icon: const Icon(Icons.qr_code_scanner),
                                  label: const Text('Personal Pickup'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _chooseFulfillment(
                                    context,
                                    order.id,
                                    'Delivery',
                                  ),
                                  icon: const Icon(Icons.local_shipping),
                                  label: const Text('Request Delivery'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Pickup QR + OTP — shown after customer chooses Personal Pickup
                if (order.status == LaundryStatus.readyForPickup &&
                    order.isPersonalPickup) ...[
                  _PickupQrCard(order: order),
                  const SizedBox(height: 16),
                ],

                // Fulfillment status — shown after customer has chosen
                if (order.hasFulfillmentChoice && order.status != LaundryStatus.completed) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            order.isPersonalPickup
                                ? Icons.qr_code_scanner
                                : Icons.local_shipping,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Fulfillment',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                FulfillmentBadge(method: order.fulfillmentMethod),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

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
                              'Machine Activity',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...order.machineHistory.map((h) {
                              final type = (h['type'] as String?) ?? '';
                              final number = '${h['number'] ?? ''}';
                              final label = (h['label'] as String?) ?? '';
                              final completedAt = h['completedAt'];
                              final isWash = type == 'wash';
                              final iconColor = isWash ? Colors.blue : Colors.deepPurple;
                              final typeLabel = isWash ? 'Wash' : 'Dry';
                              final timestamp = completedAt != null
                                  ? DateHelper.formatDateTime(
                                      completedAt is DateTime
                                          ? completedAt
                                          : (completedAt as Timestamp).toDate(),
                                    )
                                  : null;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: iconColor.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: iconColor.withValues(alpha: 0.15),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isWash ? Icons.water_drop : Icons.air,
                                      size: 18,
                                      color: iconColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            label.isNotEmpty ? label : '$typeLabel #$number',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          if (timestamp != null)
                                            Text(
                                              'Completed: $timestamp',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.check_circle,
                                      size: 16,
                                      color: AppColors.success,
                                    ),
                                  ],
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
                          'Transaction Details',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow('Weight', order.hasVerifiedActualWeight ? '${order.actualWeight!.toStringAsFixed(1)} kg (verified)' : '${order.weight} kg'),
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
                        if (order.paymentMethod != 'GCash' &&
                            order.remittanceStatus != null &&
                            order.remittanceStatus!.isNotEmpty)
                          _buildDetailRow(
                            'Remittance',
                            order.remittanceStatus == 'Remitted'
                                ? 'Cash turned over to admin'
                                : 'Awaiting admin confirmation',
                            color: order.remittanceStatus == 'Remitted'
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                        if (order.distanceKm != null)
                          _buildDetailRow(
                            'Distance',
                            '${order.distanceKm!.toStringAsFixed(1)} km',
                          ),
                        const Divider(),
                        _buildDetailRow(
                          'Final Amount',
                          CurrencyHelper.formatSimple(
                            order.finalAmount ?? order.totalAmount,
                          ),
                          isBold: true,
                          color: AppColors.primary,
                        ),
                        if (order.amountPaid > 0)
                          _buildDetailRow(
                            'Amount Paid',
                            CurrencyHelper.formatSimple(order.amountPaid),
                          ),
                        if (order.outstandingBalance > 0)
                          _buildDetailRow(
                            'Balance Due',
                            CurrencyHelper.formatSimple(order.outstandingBalance),
                            isBold: true,
                            color: AppColors.warning,
                          ),
                        if (order.pendingRefund > 0)
                          _buildDetailRow(
                            'Refund Due',
                            CurrencyHelper.formatSimple(order.pendingRefund),
                            isBold: true,
                            color: AppColors.info,
                          ),
                      ],
                    ),
                  ),
                ),
                // View Receipt / View Scale Proof buttons
                if (order.paymentMethod == 'GCash' || order.weightProofId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Proof & Receipts',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            if (order.paymentMethod == 'GCash')
                              FutureBuilder<QuerySnapshot>(
                                future: FirebaseFirestore.instance
                                    .collection('payments')
                                    .where('orderId', isEqualTo: order.id)
                                    .limit(1)
                                    .get(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const SizedBox.shrink();
                                  }
                                  final docs = snapshot.data?.docs ?? [];
                                  if (docs.isEmpty) return const SizedBox.shrink();
                                  final data = docs.first.data() as Map<String, dynamic>;
                                  final receiptUrl = data['receiptImageUrl'] as String?;
                                  final receiptProofId = data['receiptProofId'] as String?;
                                  final refNumber = data['referenceNumber'] as String?;
                                  final hasReceipt =
                                      (receiptUrl != null && receiptUrl.isNotEmpty) ||
                                      (receiptProofId != null && receiptProofId.isNotEmpty);
                                  if (!hasReceipt) {
                                    return const SizedBox.shrink();
                                  }
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (refNumber != null)
                                        _buildDetailRow('GCash Ref #', refNumber),
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          icon: const Icon(Icons.receipt_long, size: 18),
                                          label: const Text('View GCash Receipt'),
                                          onPressed: () => _showReceiptDialog(
                                            context,
                                            order.id,
                                            receiptProofId: receiptProofId,
                                            imageUrl: receiptUrl,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            if (order.weightProofId != null)
                              Padding(
                                padding: EdgeInsets.only(top: order.paymentMethod == 'GCash' ? 8 : 0),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.scale, size: 18),
                                    label: const Text('View Scale Proof'),
                                    onPressed: () => _showScaleProofDialog(context, order),
                                  ),
                                ),
                              ),
                          ],
                        ),
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
                      subtitle: StaffNameWidget(
                        staffId: order.assignedTo,
                        prefix: '',
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

  void _showReceiptDialog(
    BuildContext context,
    String orderId, {
    String? receiptProofId,
    String? imageUrl,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('GCash Receipt', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            Flexible(
              child: InteractiveViewer(
                child: _ReceiptImage(
                  orderId: orderId,
                  receiptProofId: receiptProofId,
                  imageUrl: imageUrl,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showScaleProofDialog(BuildContext context, OrderModel order) {
    final proofId = order.weightProofId;
    if (proofId == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Scale Proof', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            if (order.actualWeight != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Measured: ${order.actualWeight!.toStringAsFixed(1)} kg',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 8),
            Flexible(
              child: FutureBuilder<Uint8List?>(
                future: TransactionProofService().loadImageBytes(
                  proofId: proofId,
                  orderId: order.id,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    );
                  }
                  final bytes = snapshot.data;
                  if (bytes == null) {
                    return const Padding(
                      padding: EdgeInsets.all(40),
                      child: Text('Scale proof unavailable', style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return InteractiveViewer(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  );
                },
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, OrderModel order) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppColors.error, size: 28),
            SizedBox(width: 8),
            Text('Cancel Transaction'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to cancel this transaction?',
              style: TextStyle(fontSize: 15),
            ),
            if (order.pendingRefund > 0) ...[
              const SizedBox(height: 8),
              Text(
                'A refund of ${CurrencyHelper.formatSimple(order.pendingRefund)} will be recorded for the shop to return.',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.warning,
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Transaction'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text(
              'Cancel Transaction',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final userId = context.read<AuthProvider>().user?.id ?? '';
    final reason = reasonController.text.trim();
    final success = await context.read<OrderProvider>().cancelOrder(
      orderId: order.id,
      cancelledBy: userId,
      reason: reason.isEmpty ? null : reason,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Transaction cancelled.' : 'Failed to cancel transaction.',
        ),
        backgroundColor: AppColors.error,
      ),
    );
  }

  Future<void> _chooseFulfillment(
    BuildContext context,
    String orderId,
    String method,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirm $method'),
        content: Text(
          method == 'Personal Pickup'
              ? 'You will pick up your laundry from the shop. You\'ll receive a QR code and pickup code.'
              : 'Our delivery staff will deliver your laundry to your address. A delivery fee may apply.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Confirm $method'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final provider = context.read<OrderProvider>();
    final success = await provider.chooseFulfillment(
      orderId: orderId,
      method: method,
    );

    if (!context.mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Failed to set fulfillment method.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // If personal pickup, generate credentials
    if (method == 'Personal Pickup') {
      await PickupService.generatePickupCredentials(
        orderId: orderId,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Pickup code generated! Show QR or code when picking up.'),
            ],
          ),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Delivery requested! A delivery staff will be assigned.'),
            ],
          ),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }
  String _loadStatusLabel(OrderLoadModel load) {
    switch (load.status) {
      case LaundryStatus.pending:
        return 'Pending';
      case LaundryStatus.paymentVerified:
        return 'Awaiting Machine';
      case LaundryStatus.waitingForMachine:
        return 'Waiting for Machine';
      case LaundryStatus.machineAssigned:
        return 'Machine Assigned — ${load.washerId ?? ''}';
      case LaundryStatus.washing:
        return 'Washing';
      case LaundryStatus.waitingForDryer:
        return 'Waiting for Dryer';
      case LaundryStatus.dryerAssigned:
        return 'Dryer Assigned — ${load.dryerId ?? ''}';
      case LaundryStatus.drying:
        return 'Drying';
      case LaundryStatus.folding:
        return 'Folded';
      case LaundryStatus.readyForPickup:
        return 'Ready for Pickup';
      case LaundryStatus.readyForDelivery:
        return 'Ready for Delivery';
      case LaundryStatus.outForDelivery:
        return 'Out for Delivery';
      case LaundryStatus.delivered:
        return 'Delivered';
      case LaundryStatus.pickedUp:
        return 'Picked Up';
      case LaundryStatus.completed:
        return 'Completed';
      default:
        return load.status.value;
    }
  }

  Color _loadStatusColor(OrderLoadModel load) {
    switch (load.status) {
      case LaundryStatus.washing:
      case LaundryStatus.drying:
        return AppColors.accent;
      case LaundryStatus.machineAssigned:
      case LaundryStatus.dryerAssigned:
        return AppColors.processingColor;
      case LaundryStatus.waitingForMachine:
      case LaundryStatus.waitingForDryer:
      case LaundryStatus.paymentVerified:
        return AppColors.warning;
      case LaundryStatus.folding:
      case LaundryStatus.readyForPickup:
      case LaundryStatus.readyForDelivery:
      case LaundryStatus.outForDelivery:
        return AppColors.primary;
      case LaundryStatus.delivered:
      case LaundryStatus.pickedUp:
      case LaundryStatus.completed:
        return AppColors.success;
      default:
        return Colors.grey;
    }
  }
}

/// Card showing the pickup QR code and OTP code for personal pickup.
class _PickupQrCard extends StatelessWidget {
  final OrderModel order;

  const _PickupQrCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.qr_code_scanner,
              color: AppColors.primary,
              size: 40,
            ),
            const SizedBox(height: 12),
            const Text(
              'Pickup Verification',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Show this QR code or provide the 6-digit code when picking up.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),

            // QR Code
            if (order.pickupToken != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: QrImageView(
                  data: order.pickupToken!,
                  version: QrVersions.auto,
                  size: 180,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 6-Digit OTP Code
            if (order.pickupCode != null) ...[
              const Text(
                'Backup Code',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  order.pickupCode!,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Expiration
            if (order.pickupExpiresAt != null) ...[
              Text(
                'Expires: ${DateHelper.formatDateTime(order.pickupExpiresAt!)}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Renders a GCash receipt, preferring the new Base64 proof stored in
/// `transaction_proofs`. Falls back to the legacy Firebase Storage URL.
class _ReceiptImage extends StatelessWidget {
  const _ReceiptImage({
    required this.orderId,
    this.receiptProofId,
    this.imageUrl,
  });

  final String orderId;
  final String? receiptProofId;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final proofId = receiptProofId;
    final url = imageUrl;

    if (proofId != null && proofId.isNotEmpty) {
      return FutureBuilder<Uint8List?>(
        future: TransactionProofService().loadImageBytes(
          proofId: proofId,
          orderId: orderId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(40),
              child: Text('Receipt unavailable', style: TextStyle(color: Colors.grey)),
            );
          }
          return Image.memory(bytes, fit: BoxFit.contain);
        },
      );
    }

    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (_, __, ___) => const Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
        errorBuilder: (_, __, ___) => const Padding(
          padding: EdgeInsets.all(40),
          child: Icon(Icons.broken_image, size: 48, color: Colors.grey),
        ),
      );
    }

    return const Padding(
      padding: EdgeInsets.all(40),
      child: Text('No receipt available', style: TextStyle(color: Colors.grey)),
    );
  }
}
