import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/order_load_model.dart';
import '../../../providers/order_provider.dart';
import '../../../providers/machine_provider.dart';
import '../../../engines/order_status_flow_engine.dart';
import '../../../engines/order_load_engine.dart';

/// Laundry Task screen for staff — operates on a SINGLE load.
///
/// This is the ONLY place laundry processing operations live:
///   - Start Washing  (reserved -> washing, starts the 38-min timer)
///   - Complete Washing (releases washer; auto-assigns dryer for Wash & Dry)
///   - Start Drying   (reserved -> drying, starts the 38-min timer)
///   - Complete Drying (releases dryer; marks load Completed)
///
/// Machine assignment is fully system-driven (Least Used Machine algorithm).
/// Staff never manually select a machine; they only confirm physical steps.
class LaundryTaskScreen extends StatefulWidget {
  final String orderId;
  final String? loadId;

  const LaundryTaskScreen({super.key, required this.orderId, this.loadId});

  @override
  State<LaundryTaskScreen> createState() => _LaundryTaskScreenState();
}

class _LaundryTaskScreenState extends State<LaundryTaskScreen> {
  bool _busy = false;

  /// Stream a single load. Falls back to the first active processing load of
  /// the order when no specific load id is provided (legacy navigation).
  Stream<OrderLoadModel?> _streamLoad() {
    final orderProvider = context.read<OrderProvider>();
    if (widget.loadId != null && widget.loadId!.isNotEmpty) {
      return orderProvider.streamOrderLoadById(widget.loadId!);
    }
    return orderProvider.streamOrderLoads(widget.orderId).map((loads) {
      final active = loads.where((l) => !l.status.isFinished).toList()
        ..sort((a, b) => a.loadNumber.compareTo(b.loadNumber));
      return active.isNotEmpty ? active.first : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laundry Task'),
        // Ensure staff can always go back to the main screen.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to dashboard',
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
        ),
      ),
      body: StreamBuilder<OrderLoadModel?>(
        stream: _streamLoad(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final load = snapshot.data;
          if (load == null) {
            // This load is done -> show a message with a button to return.
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
                      'This laundry task is completed!',
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst),
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
                _buildLoadCard(load),
                const SizedBox(height: 16),
                _buildMachineInfoCard(load),
                const SizedBox(height: 16),
                const Text(
                  'Actions',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildActionButtons(load),
                const SizedBox(height: 16),
                _buildStatusFlow(load),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadCard(OrderLoadModel load) {
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
                  'Order ${load.orderId.substring(0, 6).toUpperCase()} · '
                  'Load ${load.loadNumber}',
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
                      load.status.value,
                    ).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    load.status.value,
                    style: TextStyle(
                      color: _statusColor(load.status.value),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Service: ${load.serviceType}'),
            Text('Weight: ${load.weight} kg'),
          ],
        ),
      ),
    );
  }

  Widget _buildMachineInfoCard(OrderLoadModel load) {
    final washer = load.assignedWasherId;
    final dryer = load.assignedDryerId;
    if (washer == null && dryer == null) {
      return const SizedBox.shrink();
    }

    return Card(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assigned Machine',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (washer != null)
              Row(
                children: [
                  const Icon(Icons.wash, color: AppColors.primary, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Washer: $washer',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            if (washer != null && dryer != null) const SizedBox(height: 8),
            if (dryer != null)
              Row(
                children: [
                  const Icon(Icons.air, color: Colors.deepPurple, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Dryer: $dryer',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(OrderLoadModel load) {
    final serviceType = load.serviceType;
    final needsDry = OrderStatusFlowEngine.needsDrying(serviceType);
    final status = load.status.value;
    final machineProvider = context.read<MachineProvider>();

    // Completed -> show a back button.
    if (load.status.isFinished) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () =>
              Navigator.of(context).popUntil((route) => route.isFirst),
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

    // WAITING STATES (Informative placeholders)
    if (status == OrderStatusFlowEngine.statusPaymentVerified ||
        status == OrderStatusFlowEngine.statusWaitingForMachine ||
        status == OrderStatusFlowEngine.statusWaitingForDryer) {
      String label = "Waiting for System...";
      if (status == OrderStatusFlowEngine.statusWaitingForMachine) label = "Waiting for Washer...";
      if (status == OrderStatusFlowEngine.statusWaitingForDryer) label = "Waiting for Dryer...";
      
      buttons.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    // START WASHING (Machine Assigned + washer assigned)
    if (status == OrderStatusFlowEngine.statusMachineAssigned &&
        load.assignedWasherId != null) {
      buttons.add(
        _actionButton(
          label: 'Start Washing',
          icon: Icons.play_circle_fill,
          color: AppColors.processingColor,
          onPressed: () =>
              _startMachine(machineProvider, load, AppConstants.machineWasher),
        ),
      );
    }

    // COMPLETE WASHING (Washing)
    if (status == OrderStatusFlowEngine.statusWashing) {
      final nextStatus = needsDry
          ? OrderStatusFlowEngine.statusWaitingForDryer
          : OrderStatusFlowEngine.statusCompleted;
      buttons.add(
        _actionButton(
          label: 'Complete Washing',
          icon: Icons.done_all,
          color: AppColors.success,
          onPressed: () => _completeStep(
            machineProvider,
            load,
            machineType: AppConstants.machineWasher,
            nextStatus: nextStatus,
            serviceType: serviceType,
          ),
        ),
      );
    }

    // START DRYING (Dryer Assigned + dryer assigned)
    if (status == OrderStatusFlowEngine.statusDryerAssigned &&
        load.assignedDryerId != null) {
      buttons.add(
        _actionButton(
          label: 'Start Drying',
          icon: Icons.play_circle_fill,
          color: Colors.deepPurple,
          onPressed: () =>
              _startMachine(machineProvider, load, AppConstants.machineDryer),
        ),
      );
    }

    // COMPLETE DRYING (Drying) -> mark load Completed.
    if (status == OrderStatusFlowEngine.statusDrying) {
      buttons.add(
        _actionButton(
          label: 'Complete Drying',
          icon: Icons.done_all,
          color: AppColors.success,
          onPressed: () => _completeStep(
            machineProvider,
            load,
            machineType: AppConstants.machineDryer,
            nextStatus: OrderStatusFlowEngine.statusCompleted,
            serviceType: serviceType,
          ),
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

  /// Start the physical machine cycle for this load. Only valid for a
  /// reserved machine. This is the ONLY point the 38-minute timer begins.
  Future<void> _startMachine(
    MachineProvider machineProvider,
    OrderLoadModel load,
    String machineType,
  ) async {
    final machineId = machineType == AppConstants.machineWasher
        ? load.assignedWasherId
        : load.assignedDryerId;
    if (machineId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No machine assigned to this load.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final success = await machineProvider.startMachineStep(
      orderId: load.orderId,
      machineId: machineId,
      machineType: machineType,
      loadId: load.id,
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
    OrderLoadModel load, {
    required String machineType,
    required String nextStatus,
    String? serviceType,
  }) async {
    final machineId = machineType == AppConstants.machineWasher
        ? load.assignedWasherId
        : load.assignedDryerId;
    if (machineId == null) {
      await context.read<OrderProvider>().completeLoad(load);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Status updated.')));
      }
      return;
    }

    setState(() => _busy = true);
    final effective = await machineProvider.completeMachineStep(
      orderId: load.orderId,
      machineType: machineType,
      machineId: machineId,
      nextStatus: nextStatus,
      serviceType: serviceType,
      loadId: load.id,
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

  Widget _buildStatusFlow(OrderLoadModel load) {
    final statusFlow = OrderLoadEngine.getLoadFlow(load.serviceType);
    final currentIndex = statusFlow.indexOf(load.status.value);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Load Status Flow',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...List.generate(statusFlow.length, (index) {
              final isCompleted =
                  index <= currentIndex &&
                  load.status.value !=
                      OrderStatusFlowEngine.statusWaitingForMachine &&
                  load.status.value !=
                      OrderStatusFlowEngine.statusWaitingForDryer;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      isCompleted && index < currentIndex
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: (isCompleted && index < currentIndex)
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
