import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/service_provider.dart';
import '../../../providers/soap_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../models/service_model.dart';
import '../../../models/order_item_model.dart';
import '../../customer/screens/gcash_payment_screen.dart';

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

  ServiceModel? _selectedService;
  String _paymentMethod = 'Cash at Shop';
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
    if (!context.read<AuthProvider>().isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only administrators can create or print walk-in receipts.')),
      );
      return;
    }
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
      final authProvider = context.read<AuthProvider>();
      final orderProvider = context.read<OrderProvider>();
      final user = authProvider.user;
      final weight = double.parse(_weightController.text);
      final cycles = _getCycleCount(weight);
      final subtotal = cycles * _selectedService!.pricePerKg;

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

      final items = [
        OrderItemModel(
          serviceId: _selectedService!.id,
          serviceName: _selectedService!.name,
          price: _selectedService!.pricePerKg,
          quantity: cycles.toDouble(),
          unit: 'cycle(s)',
        ),
      ];

      final orderId = await orderProvider.createOrder(
        userId: user?.id ?? 'admin_walkin',
        items: items,
        weight: weight,
        customerLat: 0,
        customerLng: 0,
        subtotal: subtotal,
        soapTotal: _soapTotal,
        selectedSoaps: selectedSoapData,
        notes: _notesController.text.trim(),
        deliveryMethod: 'Drop-off', // Walk-ins are always drop-off
        orderType: 'walk_in',
        customerName: _nameController.text.trim(),
        customerPhone: _phoneController.text.trim(),
        paymentMethodOverride: _paymentMethod,
        paymentStatusOverride: _paymentMethod == 'Cash at Shop' ? 'Verified' : 'Pending Verification',
        weightStatusOverride: 'verified',
        actualWeightOverride: weight,
      );

      setState(() => _isLoading = false);

      if (mounted && orderId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Walk-in transaction created!'),
            backgroundColor: Colors.green,
          ),
        );

        if (_paymentMethod == 'GCash') {
          final submitted = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => GCashPaymentScreen(
                orderId: orderId,
                amount: subtotal + _soapTotal,
                returnOnSuccess: true,
              ),
            ),
          );
          if (submitted != true || !mounted) return;
        }

        final createdOrder = await orderProvider.getOrderById(orderId);
        if (createdOrder != null && mounted) {
          await Navigator.pushNamed(context, '/receipt-preview', arguments: createdOrder);
          if (mounted) Navigator.pop(context);
        }
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
    if (!context.read<AuthProvider>().isAdmin) {
      return const Scaffold(
        body: Center(child: Text('Administrator access is required.')),
      );
    }
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
                                Row(
                                  children: [
                                    Text(
                                      soap.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (soap.isLowStock) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.orange.shade200),
                                        ),
                                        child: Text(
                                          'LOW STOCK',
                                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.orange.shade900),
                                        ),
                                      ),
                                    ],
                                  ],
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
                          if (soap.isOutOfStock)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'OUT OF STOCK',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                              ),
                            )
                          else
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
                                    onTap: qty < soap.stockQuantity
                                        ? () => setState(() {
                                            _selectedSoaps[soap.id] = qty + 1;
                                          })
                                        : null,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Icon(
                                        Icons.add,
                                        size: 18,
                                        color: qty < soap.stockQuantity
                                            ? AppColors.primary
                                            : Colors.grey.shade300,
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
                            const Text('Collection Method:'),
                            const Text('Customer Drop-off'),
                          ],
                        ),
                        const SizedBox(height: 8),
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
                                value: 'Cash at Shop',
                                child: Text('Cash at Shop'),
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
                                _paymentMethod == 'Cash at Shop'
                                    ? 'Cash (Upon Drop-off) is verified immediately.'
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
