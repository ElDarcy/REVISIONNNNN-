import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../providers/order_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../models/order_model.dart';
import '../../../models/user_model.dart';
import '../../../engines/order_status_flow_engine.dart';
import '../../../engines/staff_assignment_engine.dart';

class ManageOrdersScreen extends StatelessWidget {
  const ManageOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Orders')),
      body: StreamBuilder(
        stream: context.read<OrderProvider>().streamAllOrders(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data ?? [];

          if (orders.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No orders found', style: TextStyle(fontSize: 18)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final distance = order.distanceKm ?? 0.0;
              return Card(
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: _getStatusColor(
                      order.status.value,
                    ).withValues(alpha: 0.1),
                    child: Icon(
                      Icons.receipt,
                      color: _getStatusColor(order.status.value),
                    ),
                  ),
                  title: Text(
                    'Order #${order.id.substring(0, 6).toUpperCase()}',
                  ),
                  subtitle: Text(
                    'Status: ${order.status.value} | Total: ${CurrencyHelper.formatWhole(order.totalAmount)}',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Weight: ${order.weight} kg'),
                          Text(
                            'Delivery Fee: ${CurrencyHelper.formatWhole(order.deliveryFee)}',
                          ),
                          Text(
                            'Payment: ${order.paymentMethod} - ${order.paymentStatus}',
                          ),
                          Text('Distance: ${distance.toStringAsFixed(1)} km'),
                          // Single "Approve & Assign Staff" action.
                          // Only shown before approval and skips rejected orders.
                          if (order.approvedAt == null &&
                              order.paymentStatus != 'Rejected')
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      icon: const Icon(
                                        Icons.check_circle,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'Approve & Assign Staff',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.success,
                                      ),
                                      onPressed: () =>
                                          _showApproveAndAssignDialog(
                                            context,
                                            order,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (order.assignedTo != null)
                            Text(
                              'Assigned to: ${order.assignedTo!.substring(0, 8)}',
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Opens the combined "Approve & Assign Staff" flow.
  ///
  /// Fetches the available laundry staff, computes their current workload,
  /// recommends the least-loaded staff member, lets the admin select (or
  /// override) a staff member, then confirms before approving + assigning.
  void _showApproveAndAssignDialog(BuildContext context, OrderModel order) {
    final searchController = TextEditingController();
    final adminId = context.read<AuthProvider>().user?.id ?? '';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Approve & Assign Staff'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OrderSummary(order: order),
                  const SizedBox(height: 12),
                  const Text(
                    'Select a staff member to approve & assign:',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  // Search field
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: 'Search staff...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  // Staff selection list with recommendation.
                  Expanded(
                    child: _StaffAssignmentList(
                      searchQuery: searchController.text,
                      onConfirm: (staffUser) {
                        Navigator.pop(dialogContext);
                        _confirmAndApprove(context, order, adminId, staffUser);
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Fetches all orders + delivery queue to compute workload data, then
  /// shows the confirmation dialog before committing the atomic approval.
  Future<void> _confirmAndApprove(
    BuildContext context,
    OrderModel order,
    String adminId,
    UserModel staff,
  ) async {
    // Show a loading indicator while computing workload data.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingWidget(message: 'Preparing approval...'),
    );

    try {
      // Fetch all orders to compute per-staff active workload and idle time.
      final ordersSnap = await FirebaseFirestore.instance
          .collection('orders')
          .get();
      final allOrders = ordersSnap.docs
          .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
          .toList();
      final workloads = StaffAssignmentEngine.countActiveOrdersByStaff(
        allOrders,
      );

      if (context.mounted) Navigator.pop(context); // close loading dialog

      if (!context.mounted) return;
      // Show the confirmation dialog.
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 12),
              Text('Confirm Approval'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Service: ${OrderStatusFlowEngine.resolveServiceType(order)}\n'
                'By approving this order:\n'
                '• The order will be marked as Approved\n'
                '• "${staff.name}" will be assigned to this order\n'
                '• Laundry loads will be created (${order.weight} kg)\n'
                '\nOrder Status: Approved\n'
                'Assigned Staff: ${staff.name}\n'
                '\nProceed with approval and assignment?',
              ),
              const SizedBox(height: 12),
              Text(
                'Current active tasks for ${staff.name}: '
                '${workloads[staff.id] ?? 0}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                final success = await context
                    .read<OrderProvider>()
                    .approveAndAssignStaff(
                      orderId: order.id,
                      adminId: adminId,
                      staffId: staff.id,
                    );
                if (context.mounted && success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.white),
                          const SizedBox(width: 8),
                          Text('Order approved & assigned to ${staff.name}!'),
                        ],
                      ),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Approval failed. The order may already be approved '
                        'or staff assigned.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
              ),
              child: const Text(
                'Approve & Assign',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // close loading dialog
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to prepare approval: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending':
      case 'Pending Payment':
      case 'Payment Pending Verification':
        return AppColors.warning;
      case 'Payment Verified':
      case 'Paid':
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
      default:
        return Colors.grey;
    }
  }
}

/// A compact summary of the order being approved.
class _OrderSummary extends StatelessWidget {
  final OrderModel order;

  const _OrderSummary({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order #${order.id.substring(0, 6).toUpperCase()}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text('Customer: ${order.customerName ?? 'N/A'}'),
          Text('Service: ${OrderStatusFlowEngine.resolveServiceType(order)}'),
          Text('Status: ${order.status.value}'),
        ],
      ),
    );
  }
}

/// A widget that fetches and displays a searchable list of staff users,
/// computes their workload, and recommends the least-loaded staff member
/// (highest priority for assignment).
class _StaffAssignmentList extends StatefulWidget {
  final String searchQuery;
  final ValueChanged<UserModel> onConfirm;

  const _StaffAssignmentList({
    required this.searchQuery,
    required this.onConfirm,
  });

  @override
  State<_StaffAssignmentList> createState() => _StaffAssignmentListState();
}

class _StaffAssignmentListState extends State<_StaffAssignmentList> {
  late Future<_StaffLoadResult> _loadFuture;
  String? _selectedStaffId;

  @override
  void initState() {
    super.initState();
    _loadFuture = _fetchStaffWithWorkload();
  }

  /// Fetch staff users AND their current workload in parallel.
  Future<_StaffLoadResult> _fetchStaffWithWorkload() async {
    // Laundry staff are stored with role 'laundry_staff' (and legacy 'staff').
    final staffSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', whereIn: ['staff', 'laundry_staff'])
        .get();
    final staffList = staffSnap.docs
        .map((doc) => UserModel.fromMap(doc.data(), doc.id))
        .toList();

    // Compute workload from all orders.
    final ordersSnap = await FirebaseFirestore.instance
        .collection('orders')
        .get();
    final allOrders = ordersSnap.docs
        .map((doc) => OrderModel.fromMap(doc.data(), doc.id))
        .toList();
    final workloads = StaffAssignmentEngine.countActiveOrdersByStaff(allOrders);
    final lastActive = StaffAssignmentEngine.lastActiveByStaff(allOrders);

    // Recommend the least-loaded staff member.
    final recommendedId = StaffAssignmentEngine.recommendStaffId(
      staffIds: staffList.map((s) => s.id).toList(),
      activeWorkloads: workloads,
      lastActive: lastActive,
    );

    return _StaffLoadResult(
      staff: staffList,
      workloads: workloads,
      recommendedId: recommendedId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StaffLoadResult>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingWidget(message: 'Loading staff list...');
        }

        final result = snapshot.data;
        if (result == null) {
          return const EmptyState(
            icon: Icons.error_outline,
            title: 'Unable to load staff',
            subtitle: 'Please try again.',
          );
        }

        var staffList = result.staff;

        // Filter by search query.
        if (widget.searchQuery.isNotEmpty) {
          final query = widget.searchQuery.toLowerCase();
          staffList = staffList.where((staff) {
            return staff.name.toLowerCase().contains(query) ||
                staff.email.toLowerCase().contains(query) ||
                staff.id.toLowerCase().contains(query);
          }).toList();
        }

        if (staffList.isEmpty) {
          return const EmptyState(
            icon: Icons.person_search,
            title: 'No Staff Available',
            subtitle: 'There are no registered staff members to assign.',
          );
        }

        // Default select the recommended staff if none selected yet.
        if (_selectedStaffId == null && result.recommendedId != null) {
          _selectedStaffId = result.recommendedId;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Recommendation banner.
            if (result.recommendedId != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      color: AppColors.success,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Recommended Staff: ${_recommendedName(result) ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Current Active Tasks: '
                            '${result.workloads[result.recommendedId] ?? 0}',
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
              ),
            Expanded(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: staffList.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final staff = staffList[index];
                  final isRecommended = staff.id == result.recommendedId;
                  final isSelected = staff.id == _selectedStaffId;
                  final workload = result.workloads[staff.id] ?? 0;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: Text(
                        staff.name.isNotEmpty
                            ? staff.name[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Flexible(
                          child: Text(
                            staff.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isRecommended)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.auto_awesome,
                              color: AppColors.success,
                              size: 16,
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '${staff.email} · Active: $workload',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isSelected ? AppColors.primary : Colors.grey,
                    ),
                    onTap: () => setState(() => _selectedStaffId = staff.id),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // Confirm action button.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle, color: Colors.white),
                label: Text(
                  'Approve & Assign: ${_selectedName(result) ?? ''}',
                  style: const TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                ),
                onPressed: _selectedStaffId == null
                    ? null
                    : () {
                        final selected = staffList
                            .where((s) => s.id == _selectedStaffId)
                            .toList();
                        if (selected.isNotEmpty) {
                          widget.onConfirm(selected.first);
                        }
                      },
              ),
            ),
          ],
        );
      },
    );
  }

  String? _recommendedName(_StaffLoadResult result) {
    if (result.recommendedId == null) return null;
    for (final s in result.staff) {
      if (s.id == result.recommendedId) return s.name;
    }
    return null;
  }

  String? _selectedName(_StaffLoadResult result) {
    if (_selectedStaffId == null) return null;
    for (final s in result.staff) {
      if (s.id == _selectedStaffId) return s.name;
    }
    return null;
  }
}

/// Holds the loaded staff list plus their computed workload metadata.
class _StaffLoadResult {
  final List<UserModel> staff;
  final Map<String, int> workloads;
  final String? recommendedId;

  const _StaffLoadResult({
    required this.staff,
    required this.workloads,
    this.recommendedId,
  });
}
