import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../providers/order_provider.dart';

class PaymentScreen extends StatelessWidget {
  final String orderId;
  final double amount;
  final String serviceName;
  final double weight;
  final int cycles;
  final double deliveryFee;
  final double subtotal;
  final List<Map<String, dynamic>> selectedSoaps;
  final double soapTotal;
  final String deliveryMethod;
  final double? promoDiscount;
  final String? promoCode;

  const PaymentScreen({
    super.key,
    required this.orderId,
    this.amount = 0,
    this.serviceName = '',
    this.weight = 0,
    this.cycles = 0,
    this.deliveryFee = 0,
    this.subtotal = 0,
    this.selectedSoaps = const [],
    this.soapTotal = 0,
    this.deliveryMethod = 'Pickup',
    this.promoDiscount,
    this.promoCode,
  });

  @override
  Widget build(BuildContext context) {
    final isPickup = deliveryMethod == 'Pickup';
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Step indicator
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Step 3: Payment',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Order Summary
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Transaction Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (serviceName.isNotEmpty)
                      _buildRow('Service', serviceName),
                    if (weight > 0)
                      _buildRow('Weight', '${weight.toStringAsFixed(1)} kg'),
                    if (cycles > 0)
                      _buildRow(
                        'Cycles',
                        '$cycles cycle${cycles > 1 ? 's' : ''}',
                      ),
                    if (subtotal > 0)
                      _buildRow(
                        'Subtotal',
                        CurrencyHelper.formatSimple(subtotal),
                      ),
                    if (soapTotal > 0) ...[
                      _buildRow(
                        'Soap Add-ons',
                        CurrencyHelper.formatSimple(soapTotal),
                      ),
                      ...selectedSoaps.map(
                        (soap) => Padding(
                          padding: const EdgeInsets.only(left: 16, bottom: 2),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '  ${soap['soapName']} x${soap['quantity']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                '₱${(soap['soapPrice'] * soap['quantity']).toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    _buildRow(
                      'Delivery Method',
                      deliveryMethod == 'Pickup' ? 'Pickup' : 'Drop-off',
                    ),
                    if (deliveryFee > 0)
                      _buildRow(
                        'Delivery Fee',
                        CurrencyHelper.formatWhole(deliveryFee),
                      ),
                    if (promoDiscount != null && promoDiscount! > 0) ...[
                      _buildRow(
                        'Promo Discount${promoCode != null ? ' ($promoCode)' : ''}',
                        '-${CurrencyHelper.formatSimple(promoDiscount!)}',
                      ),
                    ],
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total Amount:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          CurrencyHelper.formatSimple(amount),
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
            const SizedBox(height: 24),

            // Payment Methods Header
            const Text(
              'Choose Payment Method',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // GCash Card
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pushNamed(
                  context,
                  '/customer/gcash-payment',
                  arguments: {'orderId': orderId, 'amount': amount},
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Image.network(
                          'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5e/GCash_logo.svg/1200px-GCash_logo.svg.png',
                          width: 32,
                          height: 32,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.payments,
                            color: Color(0xFF1565C0),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'GCash',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Pay via GCash QR',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Cash Card (Pickup vs Drop-off)
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _handleCashOnPickup(context),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.money,
                          color: Colors.green,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPickup ? 'Cash on Pickup' : 'Cash on Drop off',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isPickup
                                  ? 'Pay when we pick up your laundry'
                                  : 'Pay in cash when you drop off your laundry at the shop',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Info Text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'After payment, an admin will verify your payment before laundry starts.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
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

  void _handleCashOnPickup(BuildContext context) {
    // Capture the screen's context (NOT the dialog's) so we can safely
    // navigate back to home after the dialog is dismissed.
    final screenContext = context;
    final isPickup = deliveryMethod == 'Pickup';
    final methodLabel = isPickup ? 'Cash on Pickup' : 'Cash on Drop off';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.money, color: Colors.green, size: 28),
            const SizedBox(width: 12),
            Text(methodLabel),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isPickup
                  ? 'You selected Cash on Pickup. '
                      'You will pay the full amount when our staff picks up your laundry.'
                  : 'You selected Cash on Drop off. '
                      'You will pay the full amount in cash when you drop off your laundry at the shop.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Amount to pay:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    CurrencyHelper.formatSimple(amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              Navigator.pop(context);

              // BUG FIX: Cash uses 'Pending Collection' (collected by staff).
              // GCash uses 'Pending Verification' (admin verifies screenshot).
              final orderProvider = screenContext.read<OrderProvider>();
              await orderProvider.updateOrderPaymentMethod(
                orderId,
                methodLabel,
                'Pending Collection',
              );

              if (screenContext.mounted) {
                ScaffoldMessenger.of(screenContext).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isPickup
                                ? 'Transaction created! Pay cash when we pickup your laundry.'
                                : 'Transaction created! Pay cash when you drop off your laundry.',
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 4),
                  ),
                );
                Navigator.pushNamed(screenContext, '/customer/home');
              }
            },
            child: Text(
              'Confirm $methodLabel',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
