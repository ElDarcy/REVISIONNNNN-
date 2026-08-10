import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/service_provider.dart';
import '../../../providers/soap_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../engines/order_status_flow_engine.dart';
import '../../../engines/order_load_engine.dart';
import '../../../models/service_model.dart';
import '../../../models/order_model.dart';

class WalkinTransactionScreen extends StatefulWidget {
  const WalkinTransactionScreen({super.key});

  @override
  State<WalkinTransactionScreen> createState() =>
      _WalkinTransactionScreenState();
}

class _WalkinTransactionScreenState extends State<WalkinTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();
  final _uuid = const Uuid();

  ServiceModel? _selectedService;
  String _paymentMethod = 'Cash';
  bool _isLoading = false;
  final Map<String, int> _selectedSoaps = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ServiceProvider>().loadServices();
      context.read<SoapProvider>().loadSoaps();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _weightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int _getCycleCount(double weight) {
    if (_selectedService == null || weight <= 0) return 0;
    return _selectedService!.getCycleCount(weight);
  }

  double get _soapTotal {
    final soapProvider = context.read<SoapProvider>();
    double total = 0;
    _selectedSoaps.forEach((soapId, qty) {
      final soap = soapProvider.getSoapById(soapId);
      if (soap != null) {
        total += soap.price * qty;
      }
    });
    return total;
  }

  Color _parseColorHex(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'detergent':
        return Icons.soap;
      case 'fabric conditioner':
        return Icons.checkroom;
      case 'bleach':
        return Icons.opacity;
      case 'laundry soap':
        return Icons.clean_hands;
      default:
        return Icons.local_laundry_service;
    }
  }

  Future<void> _createTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedService == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a service'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = context.read<AuthProvider>().user;
      final weight = double.parse(_weightController.text);
      final cycles = _getCycleCount(weight);
      final subtotal = cycles * _selectedService!.pricePerKg;
      final total = subtotal + _soapTotal;
      final orderId = _uuid.v4();

      // Build soap add-ons data
      final soapProvider = context.read<SoapProvider>();
      final selectedSoapData = <Map<String, dynamic>>[];
      _selectedSoaps.forEach((soapId, qty) {
        final soap = soapProvider.getSoapById(soapId);
        if (soap != null && qty > 0) {
          selectedSoapData.add({
            'soapId': soap.id,
            'soapName': soap.name,
            'soapPrice': soap.price,
            'quantity': qty,
            'unit': soap.unit,
          });
        }
      });

      await FirebaseFirestore.instance.collection('orders').doc(orderId).set({
        'id': orderId,
        'userId': 'walkin_${orderId.substring(0, 6)}',
        'orderType': 'walk_in',
        'createdBy': user?.id ?? '',
        'customerName': _nameController.text.trim(),
        'customerPhone': _phoneController.text.trim(),
        'serviceType': _selectedService!.name,
        'pricePerKg': _selectedService!.pricePerKg,
        'weight': weight,
        'cycles': cycles,
        'subtotal': subtotal,
        'soapTotal': _soapTotal,
        'selectedSoaps': selectedSoapData,
        'deliveryFee': 0,
        'totalAmount': total,
        'paymentMethod': _paymentMethod,
        'paymentStatus': _paymentMethod == 'Cash'
            ? 'Paid'
            : 'Pending Verification',
        // Machine assignment is NOT done here. Cash walk-in orders go to
        // 'Payment Verified' so the scheduler can split the order into loads
        // (8kg per load) and auto-assign the least-used available machine.
        // GCash walk-in orders wait for admin payment verification.
        'status': _paymentMethod == 'Cash'
            ? OrderStatusFlowEngine.statusPaymentVerified
            : OrderStatusFlowEngine.statusPaymentPendingVerification,
        'approvedAt': _paymentMethod == 'Cash'
            ? DateTime.now().toIso8601String()
            : null,
        'isWalkIn': true,
        'notes': _notesController.text.trim(),
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });

      // Create the load records for this walk-in order (8kg per load) using
      // the SAME load engine as online orders, so walk-ins share the same
      // scheduling system and machine queues.
      if (_paymentMethod == 'Cash') {
        final orderObj = OrderModel.fromMap({
          'id': orderId,
          'userId': 'walkin_${orderId.substring(0, 6)}',
          'serviceType': _selectedService!.name,
          'weight': weight,
          'deliveryMethod': 'Pickup',
        }, orderId);
        final loadIds = await OrderLoadEngine.createLoadsForOrder(
          FirebaseFirestore.instance,
          orderObj,
        );
        if (loadIds.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('orders')
              .doc(orderId)
              .update({'numberOfLoads': loadIds.length});
        }
      }

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Walk-in transaction created!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final serviceProvider = context.watch<ServiceProvider>();
    final soapProvider = context.watch<SoapProvider>();
    final services = serviceProvider.services;
    final soaps = soapProvider.availableSoaps;

    double weight = 0;
    if (_weightController.text.isNotEmpty &&
        double.tryParse(_weightController.text) != null) {
      weight = double.parse(_weightController.text);
    }
    final cycles = _getCycleCount(weight);
    final cyclePrice = _selectedService?.pricePerKg ?? 0;
    final serviceSubtotal = cycles * cyclePrice;
    final grandTotal = serviceSubtotal + _soapTotal;

    return Scaffold(
      appBar: AppBar(title: const Text('Walk-in Transaction')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Customer Information
              const Text(
                'Customer Information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _nameController,
                labelText: 'Customer Name',
                hintText: 'Enter full name',
                prefixIcon: const Icon(Icons.person),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _phoneController,
                labelText: 'Phone Number',
                hintText: '09xxxxxxxxx',
                keyboardType: TextInputType.phone,
                prefixIcon: const Icon(Icons.phone),
              ),
              const SizedBox(height: 24),

              // Service Selection
              const Text(
                'Select Service',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (services.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Loading services...'),
                  ),
                )
              else
                ...services.map((service) {
                  final isSelected = _selectedService?.id == service.id;
                  return Card(
                    color: isSelected
                        ? const Color(0xFF1565C0).withValues(alpha: 0.1)
                        : null,
                    child: RadioListTile<ServiceModel>(
                      title: Text(service.name),
                      subtitle: Text(
                        '₱${service.pricePerKg.toStringAsFixed(0)}/cycle (up to ${service.maxKgPerCycle.toStringAsFixed(0)}kg)',
                      ),
                      value: service,
                      groupValue: _selectedService,
                      onChanged: (v) {
                        setState(() => _selectedService = v);
                      },
                    ),
                  );
                }),
              const SizedBox(height: 16),

              // Weight & Details
              const Text(
                'Weight & Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _weightController,
                labelText: 'Weight (kg)',
                hintText: 'e.g. 3.5',
                keyboardType: TextInputType.number,
                prefixIcon: const Icon(Icons.monitor_weight),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (double.tryParse(v) == null) return 'Invalid number';
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              if (cycles > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Cycles needed: $cycles cycle${cycles > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _notesController,
                labelText: 'Notes (Optional)',
                maxLines: 2,
              ),
              const SizedBox(height: 24),

              // Soap Add-ons
              const Text(
                'Soap Add-ons',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Select soaps to add to the laundry',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (soaps.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No soaps available'),
                  ),
                )
              else
                ...soaps.map((soap) {
                  final qty = _selectedSoaps[soap.id] ?? 0;
                  final color = _parseColorHex(soap.colorHex);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _getCategoryIcon(soap.category),
                              color: color,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  soap.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '₱${soap.price.toStringAsFixed(0)}/${soap.unit}',
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: qty > 0
                                      ? () => setState(() {
                                          _selectedSoaps[soap.id] = qty - 1;
                                          if (_selectedSoaps[soap.id]! <= 0) {
                                            _selectedSoaps.remove(soap.id);
                                          }
                                        })
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.remove,
                                      size: 18,
                                      color: qty > 0
                                          ? AppColors.primary
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  child: Text(
                                    '$qty',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => setState(() {
                                    _selectedSoaps[soap.id] = qty + 1;
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.add,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 16),

              // Summary & Payment
              if (weight > 0 && _selectedService != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Service:'),
                            Text(_selectedService!.name),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Weight:'),
                            Text('${weight.toStringAsFixed(1)} kg'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Cycles:'),
                            Text(
                              '$cycles cycle${cycles > 1 ? 's' : ''}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Subtotal:'),
                            Text(
                              CurrencyHelper.formatSimple(serviceSubtotal),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        if (_soapTotal > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Soap Add-ons:',
                                style: TextStyle(color: Colors.grey),
                              ),
                              Text(
                                CurrencyHelper.formatSimple(_soapTotal),
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            Text(
                              CurrencyHelper.formatSimple(grandTotal),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Payment Method
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Payment Method:'),
                          DropdownButton<String>(
                            value: _paymentMethod,
                            items: const [
                              DropdownMenuItem(
                                value: 'Cash',
                                child: Text('Cash'),
                              ),
                              DropdownMenuItem(
                                value: 'GCash',
                                child: Text('GCash'),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _paymentMethod = v!),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 16,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _paymentMethod == 'Cash'
                                    ? 'Cash payment is marked as Paid immediately.'
                                    : 'GCash payment will need admin verification.',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              CustomButton(
                text: 'Create Transaction',
                isLoading: _isLoading,
                onPressed: _createTransaction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
