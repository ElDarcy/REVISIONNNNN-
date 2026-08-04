import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../models/order_model.dart';
import '../../../providers/order_provider.dart';
import '../../../providers/machine_provider.dart';
import '../../../engines/order_status_flow_engine.dart';

/// Laundry Tasks screen for staff.
///
/// This is the ONLY place laundry processing operations live:
///   - Start Washing  (reserved -> washing, starts the 38-min timer)
///   - Complete Washing (releases washer; auto-assigns dryer for Wash & Dry)
///   - Start Drying   (reserved -> drying, starts the 38-min timer)
///   - Complete Drying (releases dryer)
///
/// Machine assignment is fully system-driven (Least Used Machine algorithm).
/// Staff never manually select a machine.
class LaundryTaskScreen extends StatefulWidget {
  final String orderId;

  const LaundryTaskScreen({super.key, required this.orderId});

  @override
  State<LaundryTaskScreen> createState() => _LaundryTaskScreenState();
}

class _LaundryTaskScreenState extends State<LaundryTaskScreen> {
  bool _busy = false;

  /// Resolve the service type for an order.
  String _serviceType(OrderModel order) =>
      OrderStatusFlowEngine.resolveServiceType(order);

  /// Stream a single order by id, or the first active processing order when
  /// no specific order id is provided.
  Stream<OrderModel?> _streamOrder() {
    if (widget.orderId.isNotEmpty) {
      return context.read<OrderProvider>().streamOrderById(widget.orderId);
    }
    return context.read<OrderProvider>().streamAllOrders().map((orders) {
      final active =
          orders
              .where(
                (o) =>
                    o.status.isProcessing ||
                    o.status.value ==
                        OrderStatusFlowEngine.statusMachineAssigned ||
                    o.status.value == OrderStatusFlowEngine.statusDryerAssigned,
              )
              .toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return active.isNotEmpty ? active.first : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laundry Tasks'),
        // Ensure staff can always go back to the main screen.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to dashboard',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: StreamBuilder<OrderModel?>(
        stream: _streamOrder(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final order = snapshot.data;
          if (order == null) {
            // All tasks done -> show a message with a button to return.
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 64,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'All laundry tasks completed!',
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        label: const Text(
                          'Back to Dashboard',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOrderCard(order),
                const SizedBox(height: 16),
                _buildMachineInfoCard(order),
                const SizedBox(height: 16),
                const Text(
                  'Actions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildActionButtons(order),
                const SizedBox(height: 16),
                _buildStatusFlow(order),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderCard(OrderModel order) {
    return Card(
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
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(
                      order.status.value,
                    ).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    order.status.value,
                    style: TextStyle(
                      color: _statusColor(order.status.value),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Service: ${_serviceType(order)}'),
            Text('Weight: ${order.weight} kg'),
            Text('Total: ${CurrencyHelper.formatSimple(order.totalAmount)}'),
            if (order.paymentStatus.isNotEmpty)
              Text('Payment: ${order.paymentStatus}'),
          ],
        ),
      ),
    );
  }

  Widget _buildMachineInfoCard(OrderModel order) {
    final machineId = order.assignedMachineId;
    if (machineId == null) return const SizedBox.shrink();

    final type = order.assignedMachineType ?? '';
    final number = order.assignedMachineNumber;
    final label = type == AppConstants.machineWasher ? 'Wash' : 'Dry';

    return Card(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              type == AppConstants.machineWasher ? Icons.wash : Icons.air,
              color: AppColors.primary,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assigned Machine',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    number != null ? '$label Machine #$number' : machineId,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(OrderModel order) {
    final serviceType = _serviceType(order);
    final needsDry = OrderStatusFlowEngine.needsDrying(serviceType);
    final status = order.status.value;
    final machineProvider = context.read<MachineProvider>();

    // Completed / cancelled -> show a back button.
    if (status == 'Completed' || status == 'Cancelled') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          label: const Text(
            'Back to Dashboard',
            style: TextStyle(color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
    }

    final buttons = <Widget>[];

    // START WASHING (Machine Assigned + washer)
    if (status == OrderStatusFlowEngine.statusMachineAssigned &&
        order.assignedMachineType == AppConstants.machineWasher) {
      buttons.add(
        _actionButton(
          label: 'Start Washing',
          icon: Icons.play_circle_fill,
          color: AppColors.processingColor,
          onPressed: () =>
              _startMachine(machineProvider, order, AppConstants.machineWasher),
        ),
      );
    }

    // COMPLETE WASHING (Washing)
    if (status == OrderStatusFlowEngine.statusWashing) {
      final nextStatus = needsDry
          ? OrderStatusFlowEngine.statusWaitingForDryer
          : OrderStatusFlowEngine.readyStatus(order);
      buttons.add(
        _actionButton(
          label: 'Complete Washing',
          icon: Icons.done_all,
          color: AppColors.success,
          onPressed: () => _completeStep(
            machineProvider,
            order,
            machineType: AppConstants.machineWasher,
            nextStatus: nextStatus,
            serviceType: serviceType,
          ),
        ),
      );
    }

    // START DRYING (Dryer Assigned or Machine Assigned with dryer type)
    if (status == OrderStatusFlowEngine.statusDryerAssigned ||
        (status == OrderStatusFlowEngine.statusMachineAssigned &&
            order.assignedMachineType == AppConstants.machineDryer)) {
      buttons.add(
        _actionButton(
          label: 'Start Drying',
          icon: Icons.play_circle_fill,
          color: Colors.deepPurple,
          onPressed: () =>
              _startMachine(machineProvider, order, AppConstants.machineDryer),
        ),
      );
    }

    // COMPLETE DRYING (Drying)
    if (status == OrderStatusFlowEngine.statusDrying) {
      buttons.add(
        _actionButton(
          label: 'Complete Drying',
          icon: Icons.done_all,
          color: AppColors.success,
          onPressed: () => _completeStep(
            machineProvider,
            order,
            machineType: AppConstants.machineDryer,
            nextStatus: OrderStatusFlowEngine.readyStatus(order),
            serviceType: serviceType,
          ),
        ),
      );
    }

    // Ready status -> Completed (for pickup/delivery).
    if (status == OrderStatusFlowEngine.statusReadyForPickup ||
        status == OrderStatusFlowEngine.statusReadyForDelivery) {
      buttons.add(
        _actionButton(
          label: 'Mark as Completed',
          icon: Icons.check_circle,
          color: AppColors.success,
          onPressed: () async {
            setState(() => _busy = true);
            await context.read<OrderProvider>().updateOrderStatus(
              order.id,
              'Completed',
            );
            setState(() => _busy = false);
          },
        ),
      );
    }

    if (buttons.isEmpty) {
      return const Text(
        'No action available for the current status.',
        style: TextStyle(color: Colors.grey),
      );
    }

    return Column(
      children: [
        for (final b in buttons) ...[b, const SizedBox(height: 8)],
      ],
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : onPressed,
        icon: Icon(icon, color: Colors.white, size: 18),
        label: Text(label, style: const TextStyle(color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  /// Start the physical machine cycle. Only valid for a reserved machine.
  /// This is the ONLY point the 38-minute timer begins.
  Future<void> _startMachine(
    MachineProvider machineProvider,
    OrderModel order,
    String machineType,
  ) async {
    final machineId = order.assignedMachineId;
    if (machineId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No machine assigned to this order.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final success = await machineProvider.startMachineStep(
      orderId: order.id,
      machineId: machineId,
      machineType: machineType,
    );
    setState(() => _busy = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Machine started. Timer running.'
              : 'Failed to start machine. Ensure it is reserved.',
        ),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
  }

  Future<void> _completeStep(
    MachineProvider machineProvider,
    OrderModel order, {
    required String machineType,
    required String nextStatus,
    String? serviceType,
  }) async {
    final machineId = order.assignedMachineId;
    if (machineId == null) {
      await context.read<OrderProvider>().updateOrderStatus(
        order.id,
        nextStatus,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Status updated.')));
      }
      return;
    }

    setState(() => _busy = true);
    final effective = await machineProvider.completeMachineStep(
      orderId: order.id,
      machineType: machineType,
      machineId: machineId,
      nextStatus: nextStatus,
      serviceType: serviceType,
    );
    setState(() => _busy = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          effective
              ? 'Machine released. Status updated.'
              : 'Failed to complete step.',
        ),
      ),
    );
  }

  Widget _buildStatusFlow(OrderModel order) {
    final statusFlow = OrderStatusFlowEngine.getFullFlow(order);
    final currentIndex = statusFlow.indexOf(order.status.value);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Status Flow',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...List.generate(statusFlow.length, (index) {
              final isCompleted = index <= currentIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      isCompleted
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: isCompleted
                          ? AppColors.success
                          : Colors.grey.shade400,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      statusFlow[index],
                      style: TextStyle(
                        fontWeight: index == currentIndex
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isCompleted ? Colors.black87 : Colors.grey,
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
  }

  Color _statusColor(String status) {
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
      case 'Machine Assigned':
      case 'Dryer Assigned':
        return AppColors.processingColor;
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
