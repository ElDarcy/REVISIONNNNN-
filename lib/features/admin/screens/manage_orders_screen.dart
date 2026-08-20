import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../core/utils/date_helper.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/status_display_helper.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/staff_name_widget.dart';
import '../../../providers/order_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../models/order_model.dart';
import '../../../models/laundry_status_model.dart';
import '../../../models/user_model.dart';
import '../../../engines/order_status_flow_engine.dart';
import '../../../engines/order_scheduling_gate.dart';
import '../../../engines/staff_assignment_engine.dart';

class ManageOrdersScreen extends StatefulWidget {
  const ManageOrdersScreen({super.key});

  @override
  State<ManageOrdersScreen> createState() => _ManageOrdersScreenState();
}

class _ManageOrdersScreenState extends State<ManageOrdersScreen> {
  String _filterType = 'All';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Transactions')),
      body: StreamBuilder(
        stream: context.read<OrderProvider>().streamAllOrders(),
        builder: (screenContext, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          var orders = snapshot.data ?? [];

          if (_filterType == 'Walk-in') {
            orders = orders.where((o) => o.orderType == 'walk_in').toList();
          } else if (_filterType == 'Online') {
            orders = orders.where((o) => o.orderType != 'walk_in').toList();
          }

          if (orders.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No transactions found', style: TextStyle(fontSize: 18)),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Filter Tabs
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    _buildFilterChip('All'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Walk-in'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Online'),
                    const Spacer(),
                    Text(
                      '${orders.length} transaction(s)',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: orders.length,
                  itemBuilder: (itemContext, index) {
                    final order = orders[index];
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
                        title: Text(order.displayNumber),
                        subtitle: Text(
                          'Status: ${order.status.value} | Total: ${CurrencyHelper.formatWhole(order.totalAmount)}',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // ── Transaction Info ──
                                _buildInfoRow(Icons.receipt, 'Transaction', order.displayNumber),
                                if (order.customerName != null && order.customerName!.isNotEmpty)
                                  _buildInfoRow(Icons.person, 'Customer', Formatters.toTitleCase(order.customerName!)),
                                if (order.customerPhone != null && order.customerPhone!.isNotEmpty)
                                  _buildInfoRow(Icons.phone, 'Phone', order.customerPhone!),
                                _buildInfoRow(Icons.local_laundry_service, 'Service', order.serviceType ?? 'Wash & Dry'),
                                _buildInfoRow(Icons.category, 'Type', order.orderType == 'walk_in' ? 'Walk-in' : 'Online'),
                                _buildInfoRow(Icons.calendar_today, 'Date', DateHelper.formatDateTime(order.createdAt)),
                                if (order.deliveryMethod == 'Delivery' && order.deliveryAddress != null)
                                  _buildInfoRow(Icons.location_on, 'Address', order.deliveryAddress!.fullAddress.isNotEmpty
                                      ? order.deliveryAddress!.fullAddress
                                      : order.deliveryAddress!.street),
                                _buildInfoRow(Icons.attach_money, 'Amount', CurrencyHelper.formatWhole(order.totalAmount)),
                                _buildInfoRow(
                                  Icons.payment,
                                  'Payment',
                                  '${order.paymentMethod} — ${StatusDisplayHelper.paymentStatusDisplay(order.paymentStatus)}',
                                ),
                                if (order.outstandingBalance > 0)
                                  _buildInfoRow(
                                    Icons.error_outline,
                                    'Balance Due',
                                    CurrencyHelper.formatWhole(order.outstandingBalance),
                                  )
                                else if (order.pendingRefund > 0 && !order.refundSettled)
                                  _buildInfoRow(
                                    Icons.currency_exchange,
                                    'Refund Due',
                                    CurrencyHelper.formatWhole(order.pendingRefund),
                                  ),
                                if (order.paymentMethod != 'GCash' &&
                                    (order.remittanceStatus == 'Pending Remittance' || order.remittanceStatus == 'Remitted'))
                                  _buildInfoRow(
                                    Icons.account_balance,
                                    'Remittance',
                                    order.remittanceStatus == 'Remitted'
                                        ? 'Remitted'
                                        : 'Pending Remittance',
                                  ),
                                if (order.remittanceStatus == 'Pending Remittance' || order.remittanceStatus == 'Remitted') ...[
                                  if (order.remittedBy != null && order.remittedBy!.isNotEmpty)
                                    StaffNameWidget(
                                      staffId: order.remittedBy,
                                      prefix: 'Remitted by: ',
                                    ),
                                  if (order.confirmedBy != null && order.confirmedBy!.isNotEmpty)
                                    StaffNameWidget(
                                      staffId: order.confirmedBy,
                                      prefix: 'Confirmed by: ',
                                    ),
                                ],
                                if (order.distanceKm != null && order.distanceKm! > 0)
                                  _buildInfoRow(Icons.straighten, 'Distance', '${order.distanceKm!.toStringAsFixed(1)} km'),
                                const Divider(height: 24),
                                // ── Weight Verification ──
                                _buildInfoRow(
                                  Icons.monitor_weight_outlined,
                                  'Declared Weight',
                                  '${order.weight} kg',
                                ),
                                if (order.hasVerifiedActualWeight)
                                  _buildInfoRow(
                                    Icons.check_circle_outline,
                                    'Actual Weight',
                                    '${order.actualWeight} kg',
                                  ),
                                _buildInfoRow(
                                  Icons.fact_check,
                                  'Weight Status',
                                  order.weightStatus ?? 'pending',
                                ),
                                if (order.weightVerifiedBy != null && order.weightVerifiedBy!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                                        const SizedBox(width: 8),
                                        StaffNameWidget(
                                          staffId: order.weightVerifiedBy!,
                                          prefix: 'Verified by: ',
                                        ),
                                      ],
                                    ),
                                  ),
                                if (order.weightVerifiedAt != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.access_time, size: 16, color: Colors.grey),
                                        const SizedBox(width: 8),
                                        Text(
                                          DateHelper.formatDateTime(order.weightVerifiedAt!),
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (order.weightVerificationNote != null && order.weightVerificationNote!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.note_alt_outlined, size: 16, color: Colors.grey),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            order.weightVerificationNote!,
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                // ── Confirm Remittance ──
                                if (order.paymentMethod != 'GCash' &&
                                    order.paymentStatus == 'Verified' &&
                                    order.remittanceStatus == 'Pending Remittance')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.account_balance),
                                        label: const Text('Confirm Remittance'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.success,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () => _confirmRemittance(screenContext, order),
                                      ),
                                    ),
                                  ),
                                // ── Review GCash Payment ──
                                // Lets the admin approve a pending GCash payment
                                // straight from the transaction, which is the
                                // gate that lets the order progress to scheduling.
                                if (order.paymentMethod == 'GCash' &&
                                    order.paymentStatus == 'Pending Verification')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.verified_user_outlined),
                                        label: const Text('Review GCash Payment'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.processingColor,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () => Navigator.pushNamed(
                                          context,
                                          '/admin/payments',
                                        ),
                                      ),
                                    ),
                                  ),
                                // Manual staff assignment (admin exception tool — normal flow auto-assigns
                                // after payment verification). Hidden while the order is not in the
                                // laundry-eligible phase (e.g. a pickup whose laundry is not at the shop
                                // yet — only the delivery staff may be assigned for that leg).
                                if (!_isStaffAssigned(order) &&
                                    order.paymentStatus != 'Rejected' &&
                                    _canAssignLaundryStaff(order))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            icon: const Icon(Icons.person_add_alt_1, color: Colors.white, size: 18),
                                            label: const Text(
                                              'Assign Staff',
                                              style: TextStyle(color: Colors.white),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: AppColors.success,
                                            ),
                                            onPressed: () => _showAssignStaffDialog(screenContext, order),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (_isStaffAssigned(order))
                                  StaffNameWidget(
                                    staffId: order.assignedTo ?? order.staffId,
                                    prefix: 'Assigned to: ',
                                  ),
                                // ── Cancel Transaction (admin) ──
                                if (!order.status.isFinished &&
                                    order.status != LaundryStatus.cancelled)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.cancel_outlined,
                                          size: 18,
                                        ),
                                        label: const Text('Cancel Transaction'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: AppColors.error,
                                          side: const BorderSide(
                                            color: AppColors.error,
                                          ),
                                        ),
                                        onPressed: () => _confirmAdminCancel(
                                          screenContext,
                                          order,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final selected = _filterType == label;
    return FilterChip(
      label: Text(label, style: TextStyle(
        fontSize: 13,
        color: selected ? Colors.white : Colors.grey.shade700,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      )),
      selected: selected,
      onSelected: (_) => setState(() => _filterType = label),
      selectedColor: AppColors.primary,
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label: ', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

void _confirmRemittance(BuildContext context, OrderModel order) {
    final amount = order.totalAmount;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.account_balance, color: AppColors.success, size: 28),
            SizedBox(width: 8),
            Text('Confirm Remittance'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirm that ₱${amount.toStringAsFixed(2)} cash has been physically received from:',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 8),
            StaffNameWidget(
              staffId: order.remittedBy,
              prefix: 'Staff: ',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final adminId = context.read<AuthProvider>().user?.id ?? '';
              final success = await context.read<OrderProvider>().confirmRemittance(
                orderId: order.id,
                adminId: adminId,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'Remittance confirmed!' : 'Failed to confirm remittance.',
                    ),
                    backgroundColor: success ? AppColors.success : AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmAdminCancel(BuildContext screenContext, OrderModel order) {
    final reasonController = TextEditingController();
    showDialog(
      context: screenContext,
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
              'Are you sure you want to cancel this transaction? This cannot be undone.',
              style: TextStyle(fontSize: 15),
            ),
            if (order.pendingRefund > 0) ...[
              const SizedBox(height: 8),
              Text(
                'A refund of ${CurrencyHelper.formatWhole(order.pendingRefund)} will be recorded for the customer.',
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
            onPressed: () async {
              Navigator.pop(ctx, true);
              final adminId = ctx.read<AuthProvider>().user?.id ?? '';
              final reason = reasonController.text.trim();
              final success = await ctx.read<OrderProvider>().cancelOrder(
                orderId: order.id,
                cancelledBy: adminId,
                reason: reason.isEmpty ? null : reason,
                isAdmin: true,
              );
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Transaction cancelled.'
                          : 'Failed to cancel transaction.',
                    ),
                    backgroundColor: success ? AppColors.error : AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text(
              'Cancel Transaction',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Simple transaction approval — no staff selection.
  /// Staff is auto-assigned by the system.
  /// Opens the manual staff assignment flow (admin override).
  ///
  /// Fetches the available laundry staff, computes their current workload,
  /// recommends the least-loaded staff member, lets the admin select (or
  /// override) a staff member, then confirms the assignment.
  void _showAssignStaffDialog(BuildContext screenContext, OrderModel order) {
    final searchController = TextEditingController();
    final adminId = screenContext.read<AuthProvider>().user?.id ?? '';

    showDialog(
      context: screenContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (sContext, setDialogState) {
          return AlertDialog(
            title: const Text('Assign Staff (Override)'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OrderSummary(order: order),
                  const SizedBox(height: 12),
                  const Text(
                    'Select a staff member to assign:',
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
                        _confirmAndApprove(screenContext, order, adminId, staffUser);
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
    ).then((_) => searchController.dispose());
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
      builder: (_) => const LoadingWidget(message: 'Preparing assignment...'),
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
              Icon(Icons.person_add_alt_1, color: Colors.green, size: 28),
              SizedBox(width: 12),
              Text('Confirm Staff Assignment'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Service: ${OrderStatusFlowEngine.resolveServiceType(order)}\n'
                'By assigning this transaction:\n'
                '• "${staff.name}" will be assigned to this transaction\n'
                '• Laundry processing starts once payment and the verified '
                'weight are in place\n'
                '\nAssigned Staff: ${staff.name}\n'
                '\nProceed with assignment?',
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
                final orderProvider = context.read<OrderProvider>();
                Navigator.pop(dialogContext);

                final success = await orderProvider.assignStaff(
                  orderId: order.id,
                  adminId: adminId,
                  staffId: staff.id,
                );

                if (!context.mounted) return;

                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.white),
                          const SizedBox(width: 8),
                          Text('Staff assigned to ${order.displayNumber}!'),
                        ],
                      ),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Assignment failed. The transaction may already have '
                        'a staff assigned.',
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
                'Assign Staff',
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
            content: Text('Failed to prepare assignment: $e'),
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

  bool _isStaffAssigned(OrderModel order) {
    return order.assignedTo != null || order.staffId != null;
  }

  /// A laundry staff may only be manually assigned once the order is in the
  /// laundry-eligible phase — i.e. the pickup laundry is already at the shop
  /// (and, for cash pickup, the cash was remitted). Before that, only the
  /// delivery staff handles the pickup leg.
  bool _canAssignLaundryStaff(OrderModel order) {
    return OrderSchedulingGate.resolveAssignmentPhase(order.toMap()) ==
        AssignmentPhase.laundry;
  }
}

/// A compact summary of the order being assigned.
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
            order.displayNumber,
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
