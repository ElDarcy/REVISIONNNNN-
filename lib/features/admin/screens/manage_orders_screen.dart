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
                          // Approve Order button (starts the laundry timer).
                          // Only shown before approval.
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
                                        'Approve Order',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.success,
                                      ),
                                      onPressed: () =>
                                          _confirmApproveOrder(context, order),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (order.assignedTo == null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                      ),
                                      onPressed: () => _showAssignStaffDialog(
                                        context,
                                        order.id,
                                      ),
                                      child: const Text(
                                        'Assign Staff',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
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

  Future<void> _confirmApproveOrder(
    BuildContext context,
    OrderModel order,
  ) async {
    final adminId = context.read<AuthProvider>().user?.id ?? '';
    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text('Approve Order'),
          ],
        ),
        content: Text(
          'Service: ${OrderStatusFlowEngine.resolveServiceType(order)}\n'
          'By approving this order:\n'
          '• Payment status will be set to Verified\n'
          '• Laundry will start according to service type\n'
          '• Laundry timer will start (38 minutes per cycle)\n'
          '\nProceed with approval?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final success = await context.read<OrderProvider>().approveOrder(
                order.id,
                adminId,
              );
              if (context.mounted && success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 8),
                        Text('Order approved! Laundry timer started.'),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
            child: const Text('Approve', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAssignStaffDialog(BuildContext context, String orderId) {
    final searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Assign Staff'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  // Staff list
                  Expanded(
                    child: _StaffList(
                      searchQuery: searchController.text,
                      onStaffSelected: (staffUser) {
                        Navigator.pop(dialogContext);
                        context.read<OrderProvider>().assignStaff(
                          orderId,
                          staffUser.id,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Staff "${staffUser.name}" assigned successfully!',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
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

/// A widget that fetches and displays a searchable list of staff users.
class _StaffList extends StatefulWidget {
  final String searchQuery;
  final ValueChanged<UserModel> onStaffSelected;

  const _StaffList({required this.searchQuery, required this.onStaffSelected});

  @override
  State<_StaffList> createState() => _StaffListState();
}

class _StaffListState extends State<_StaffList> {
  late Future<List<UserModel>> _staffFuture;

  @override
  void initState() {
    super.initState();
    _staffFuture = _fetchStaffUsers();
  }

  Future<List<UserModel>> _fetchStaffUsers() async {
    try {
      // Laundry staff are stored with role 'laundry_staff' (and legacy
      // 'staff'). Query for both so all registered laundry staff appear.
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', whereIn: ['staff', 'laundry_staff'])
          .get();
      return snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('Error fetching staff users: $e');
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<UserModel>>(
      future: _staffFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingWidget(message: 'Loading staff list...');
        }

        var staffList = snapshot.data ?? [];

        // Filter by search query
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

        return ListView.separated(
          shrinkWrap: true,
          itemCount: staffList.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final staff = staffList[index];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Text(
                  staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                staff.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(staff.email, style: const TextStyle(fontSize: 12)),
              trailing: Text(
                '#${staff.id.substring(0, 6).toUpperCase()}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              onTap: () => widget.onStaffSelected(staff),
            );
          },
        );
      },
    );
  }
}
