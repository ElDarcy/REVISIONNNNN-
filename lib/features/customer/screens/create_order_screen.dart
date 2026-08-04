import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../../../core/utils/validators.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/service_provider.dart';
import '../../../providers/soap_provider.dart';
import '../../../models/service_model.dart';
import '../../../models/soap_model.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({super.key});

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();
  ServiceModel? _selectedService;
  final Map<String, int> _selectedSoaps = {}; // soapId -> quantity

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
    _weightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int _getCycleCount(double weight) {
    if (_selectedService == null || weight <= 0) return 0;
    return _selectedService!.getCycleCount(weight);
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

  Future<void> _proceedToCheckout() async {
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

    final weight = double.parse(_weightController.text);
    final cycles = _getCycleCount(weight);

    // Build list of selected soaps with details
    final soapProvider = context.read<SoapProvider>();
    final selectedSoapList = <Map<String, dynamic>>[];
    _selectedSoaps.forEach((soapId, qty) {
      final soap = soapProvider.getSoapById(soapId);
      if (soap != null && qty > 0) {
        selectedSoapList.add({
          'soapId': soap.id,
          'soapName': soap.name,
          'soapPrice': soap.price,
          'quantity': qty,
          'unit': soap.unit,
        });
      }
    });

    if (!mounted) return;

    Navigator.pushNamed(
      context,
      '/customer/checkout',
      arguments: {
        'serviceId': _selectedService!.id,
        'serviceName': _selectedService!.name,
        'pricePerKg': _selectedService!.pricePerKg,
        'weight': weight,
        'cycles': cycles,
        'notes': _notesController.text.trim(),
        'selectedSoaps': selectedSoapList,
        'soapTotal': _soapTotal,
      },
    );
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
    final soapTotal = _soapTotal;
    final grandTotal = serviceSubtotal + soapTotal;

    return Scaffold(
      appBar: AppBar(title: const Text('New Order')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    child: Text('No services available'),
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
                      onChanged: (value) {
                        setState(() {
                          _selectedService = value;
                        });
                      },
                    ),
                  );
                }),
              const SizedBox(height: 24),

              // Weight & Details
              const Text(
                'Weight & Details',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _weightController,
                labelText: 'Estimated Weight (kg)',
                hintText: 'e.g. 3.5',
                keyboardType: TextInputType.number,
                prefixIcon: const Icon(Icons.monitor_weight),
                validator: Validators.validateWeight,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: _notesController,
                labelText: 'Special Instructions (Optional)',
                hintText: 'e.g., Separate whites and colors',
                maxLines: 3,
                prefixIcon: const Icon(Icons.note_outlined),
              ),
              const SizedBox(height: 24),

              // Soap Add-ons Section
              const Text(
                'Soap Add-ons',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Select soaps to add to your laundry',
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
                          // Soap icon
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
                          // Soap info
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
                          // Quantity selector
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

              // Summary Card
              if (weight > 0 && _selectedService != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Card(
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
                              const Text('Cycles Needed:'),
                              Text(
                                '$cycles cycle${cycles > 1 ? 's' : ''}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1565C0),
                                ),
                              ),
                            ],
                          ),
                          if (soapTotal > 0) ...[
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Soap Add-ons:',
                                  style: TextStyle(color: Colors.grey),
                                ),
                                Text(
                                  CurrencyHelper.formatSimple(soapTotal),
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
                                'Estimated Total:',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                CurrencyHelper.formatSimple(grandTotal),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1565C0),
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              CustomButton(
                text: 'Proceed to Checkout',
                onPressed: _proceedToCheckout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
