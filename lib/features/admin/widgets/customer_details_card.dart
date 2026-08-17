import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/formatters.dart';

/// A card that displays detailed customer information for admin verification.
/// Uses a static cache to prevent UI blinking during transaction list updates.
class CustomerDetailsCard extends StatefulWidget {
  final String userId;

  const CustomerDetailsCard({super.key, required this.userId});

  @override
  State<CustomerDetailsCard> createState() => _CustomerDetailsCardState();
}

class _CustomerDetailsCardState extends State<CustomerDetailsCard> {
  static final Map<String, Map<String, dynamic>> _customerCache = {};
  Future<Map<String, dynamic>>? _customerFuture;

  @override
  void initState() {
    super.initState();
    _initFuture();
  }

  @override
  void didUpdateWidget(CustomerDetailsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userId != oldWidget.userId) {
      _initFuture();
    }
  }

  void _initFuture() {
    if (_customerCache.containsKey(widget.userId)) {
      _customerFuture = Future.value(_customerCache[widget.userId]);
    } else {
      _customerFuture = _fetchCustomer(widget.userId);
    }
  }

  Future<Map<String, dynamic>> _fetchCustomer(String id) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(id).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _customerCache[id] = data;
        return data;
      }
    } catch (e) {
      debugPrint('Error fetching customer details: $e');
    }
    return {};
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _customerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          );
        }

        final data = snapshot.data ?? {};
        if (data.isEmpty) return const SizedBox.shrink();

        final rawName = data['name'] as String? ?? 'N/A';
        final name = Formatters.toTitleCase(rawName);
        final phone = data['phone'] as String? ?? 'N/A';
        final address = data['address'] as String? ?? 'N/A';
        final role = data['role'] as String? ?? 'customer';

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: AppColors.primary.withValues(alpha: 0.03),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_user, color: AppColors.success, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'CUSTOMER VERIFICATION',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: AppColors.success, size: 16),
                    const SizedBox(width: 6),
                    const Text(
                      'Verified Customer',
                      style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Account matched with transaction',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const Divider(height: 24),
                _buildInfoRow('Name', name),
                _buildInfoRow('Contact', Formatters.formatPhone(phone)),
                _buildInfoRow('Address', address),
                _buildInfoRow('Verification', role.toUpperCase(), isStatus: true),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isStatus = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isStatus ? FontWeight.bold : FontWeight.w600,
              color: isStatus ? AppColors.success : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
