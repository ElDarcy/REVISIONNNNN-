import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../services/location_service.dart';
import '../../../engines/distance_engine.dart';
import '../../../engines/delivery_fee_engine.dart';
import '../../../engines/service_area_engine.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../models/order_item_model.dart';
import '../../../config/app_config.dart';

class CheckoutScreen extends StatefulWidget {
  final String serviceId;
  final String serviceName;
  final double pricePerKg;
  final double weight;
  final int cycles;
  final String notes;
  final List<Map<String, dynamic>> selectedSoaps;
  final double soapTotal;

  const CheckoutScreen({
    super.key,
    required this.serviceId,
    required this.serviceName,
    required this.pricePerKg,
    this.weight = 0,
    this.cycles = 0,
    this.notes = '',
    this.selectedSoaps = const [],
    this.soapTotal = 0,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final LocationService _locationService = LocationService();
  bool _isLoading = false;
  double _latitude = 0;
  double _longitude = 0;
  double _distance = 0;
  String _address = '';
  double _deliveryFee = 0;
  // `Pickup` is the persisted legacy value for a staff collection request.
  // Keep that value so existing orders and pricing continue to work.
  String _deliveryMethod = 'Pickup'; // Request Pickup or Drop-off

  @override
  void initState() {
    super.initState();
    // Load location in the background WITHOUT blocking the page render.
    // The checkout screen is fully usable immediately; delivery details
    // populate when the location resolves (or a default is shown).
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    try {
      final location = await _locationService.getLocationDetails().timeout(
        const Duration(seconds: 8),
      );
      final lat = location['latitude'] as double;
      final lng = location['longitude'] as double;
      final address = location['address'] as String;

      final rawDistance = DistanceEngine.distanceFromShop(lat, lng);
      final distance = DeliveryFeeEngine.roundDistance(rawDistance);
      final deliveryFee = DeliveryFeeEngine.calculateFee(distance);

      if (!mounted) return;
      setState(() {
        _latitude = lat;
        _longitude = lng;
        _address = address;
        _distance = distance;
        _deliveryFee = deliveryFee;
      });
    } catch (e) {
      // Location unavailable → keep default values so the page still works.
      debugPrint('Location load error: $e');
    }
  }

  void _createOrderAndProceed() async {
    setState(() => _isLoading = true);

    final authProvider = context.read<AuthProvider>();
    final orderProvider = context.read<OrderProvider>();
    final user = authProvider.user;

    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login first'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoading = false);
      return;
    }

    // A staff pickup request must be within the configured service area.
    if (_deliveryMethod == 'Pickup' &&
        !ServiceAreaEngine.isInServiceArea(_latitude, _longitude)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sorry, your location is ${_distance.toStringAsFixed(1)}km away. '
              'Maximum delivery radius is ${AppConfig.maxDeliveryRadiusKm.toStringAsFixed(0)}km.',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      setState(() => _isLoading = false);
      return;
    }

    final subtotal = widget.cycles * widget.pricePerKg;
    final effectiveDeliveryFee = _deliveryMethod == 'Pickup' ? _deliveryFee : 0;
    final total = subtotal + widget.soapTotal + effectiveDeliveryFee;

    // Build proper OrderItemModel list
    final items = [
      OrderItemModel(
        serviceId: widget.serviceId,
        serviceName: widget.serviceName,
        price: widget.pricePerKg,
        quantity: widget.cycles.toDouble(),
        unit: 'cycle(s)',
      ),
    ];

    final orderId = await orderProvider.createOrder(
      userId: user.id,
      items: items,
      weight: widget.weight,
      customerLat: _latitude,
      customerLng: _longitude,
      subtotal: subtotal,
      soapTotal: widget.soapTotal,
      selectedSoaps: widget.selectedSoaps,
      notes: widget.notes,
      deliveryMethod: _deliveryMethod,
    );

    setState(() => _isLoading = false);

    if (orderId != null && mounted) {
      Navigator.pushNamed(
        context,
        '/customer/payment',
        arguments: {
          'orderId': orderId,
          'amount': total,
          'serviceName': widget.serviceName,
          'weight': widget.weight,
          'cycles': widget.cycles,
          'deliveryFee': effectiveDeliveryFee,
          'subtotal': subtotal,
          'selectedSoaps': widget.selectedSoaps,
          'soapTotal': widget.soapTotal,
          'deliveryMethod': _deliveryMethod,
        },
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create order. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = widget.cycles * widget.pricePerKg;
    final effectiveDeliveryFee = _deliveryMethod == 'Pickup' ? _deliveryFee : 0;
    final total = subtotal + widget.soapTotal + effectiveDeliveryFee;

    return Scaffold(
      appBar: AppBar(title: Text('Checkout - ${widget.serviceName}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Service Summary
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Order Summary',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildSummaryRow('Service', widget.serviceName),
                          _buildSummaryRow(
                            'Price Rate',
                            '₱${widget.pricePerKg}/cycle (up to 8kg)',
                          ),
                          _buildSummaryRow(
                            'Weight',
                            '${widget.weight.toStringAsFixed(1)} kg',
                          ),
                          _buildSummaryRow(
                            'Cycles',
                            '${widget.cycles} cycle(s)',
                          ),
                          const Divider(),
                          _buildSummaryRow(
                            'Subtotal (Service)',
                            CurrencyHelper.formatSimple(subtotal),
                          ),
                          if (widget.soapTotal > 0) ...[
                            _buildSummaryRow(
                              'Soap Add-ons',
                              CurrencyHelper.formatSimple(widget.soapTotal),
                            ),
                            ...widget.selectedSoaps.map(
                              (soap) => Padding(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  bottom: 2,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '  ${soap['soapName']} x${soap['quantity']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      '₱${(soap['soapPrice'] * soap['quantity']).toStringAsFixed(2)}',
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
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Collection Method
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Collection Method',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDeliveryOption(
                                  icon: Icons.motorcycle,
                                  title: 'Request Pickup',
                                  subtitle: 'We pick up your laundry',
                                  isSelected: _deliveryMethod == 'Pickup',
                                  onTap: () => setState(() {
                                    _deliveryMethod = 'Pickup';
                                  }),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildDeliveryOption(
                                  icon: Icons.store,
                                  title: 'Drop-off',
                                  subtitle: 'Bring to our shop',
                                  isSelected: _deliveryMethod == 'Drop-off',
                                  onTap: () => setState(() {
                                    _deliveryMethod = 'Drop-off';
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Delivery Info - Only show for Pickup
                  if (_deliveryMethod == 'Pickup')
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pickup Location',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color: Color(0xFF1565C0),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _address.isNotEmpty &&
                                            _address != 'Unable to get address'
                                        ? _address
                                        : _address == 'Unable to get address'
                                        ? 'Address unavailable - location detected (${_latitude.toStringAsFixed(4)}, ${_longitude.toStringAsFixed(4)})'
                                        : 'Getting location...',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildSummaryRow(
                              'Distance from Shop',
                              '${_distance.toStringAsFixed(1)} km',
                            ),
                            _buildSummaryRow(
                              'Delivery Fee',
                              CurrencyHelper.formatWhole(_deliveryFee),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    // Show shop address for Drop-off
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Shop Location',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(
                                  Icons.store,
                                  color: Color(0xFF1565C0),
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Sabalo, Brgy. 12, Caloocan City',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  color: Color(0xFF1565C0),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Mon-Sat: 7:00 AM - 9:00 PM',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                            _buildSummaryRow('Delivery Fee', 'Free (Drop-off)'),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  // Total
                  Card(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Total Amount:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            CurrencyHelper.formatSimple(total),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1565C0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  CustomButton(
                    text: 'Place Order & Proceed to Payment',
                    onPressed: _createOrderAndProceed,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
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

  Widget _buildDeliveryOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF1565C0).withValues(alpha: 0.1)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF1565C0) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: isSelected ? const Color(0xFF1565C0) : Colors.grey,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isSelected ? const Color(0xFF1565C0) : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
