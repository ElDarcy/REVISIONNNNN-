import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/utils/currency_helper.dart';
import '../../../services/location_service.dart';
import '../../../engines/distance_engine.dart';
import '../../../engines/delivery_fee_engine.dart';
import '../../../engines/service_area_engine.dart';
import '../../../engines/engagement_pricing_engine.dart';
import '../../../models/engagement_models.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/order_provider.dart';
import '../../../models/order_item_model.dart';
import '../../../models/address_model.dart';
import '../../../services/engagement_customer_service.dart';
import '../../../services/business_configuration_service.dart';
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
  final TextEditingController _manualStreetController = TextEditingController();
  final TextEditingController _manualBarangayController = TextEditingController();
  final TextEditingController _manualCityController = TextEditingController();
  bool _isLoading = false;
  double _latitude = 0;
  double _longitude = 0;
  double _distance = 0;
  String _address = '';
  double _deliveryFee = 0;
  bool _useManualAddress = false;
  // `Pickup` is the persisted legacy value for a staff collection request.
  // Keep that value so existing orders and pricing continue to work.
  String _deliveryMethod = 'Pickup'; // Request Pickup or Drop-off

  // ── Engagement state ──
  final TextEditingController _promoController = TextEditingController();
  final EngagementCustomerService _engageApi = EngagementCustomerService();
  final BusinessConfigurationService _configApi = BusinessConfigurationService();
  Promotion? _appliedPromo;
  String? _promoError;
  bool _promoLoading = false;
  MembershipPlan? _membershipPlan;
  double _membershipDiscount = 0;

  @override
  void initState() {
    super.initState();
    _loadLocation();
    _loadMembership();
  }

  void _loadMembership() {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    _engageApi.subscription(user.id).listen((sub) {
      if (!mounted) return;
      if (sub != null && sub['status'] == 'Active') {
        final planId = sub['planId'] as String?;
        if (planId != null) {
          _configApi.watchPlans().listen((plans) {
            if (!mounted) return;
            final match = plans.where((p) => p.id == planId && p.status == 'Active');
            setState(() { _membershipPlan = match.isNotEmpty ? match.first : null; });
          });
        }
      } else {
        setState(() { _membershipPlan = null; _membershipDiscount = 0; });
      }
    });
  }

  @override
  void dispose() {
    _manualStreetController.dispose();
    _manualBarangayController.dispose();
    _manualCityController.dispose();
    _promoController.dispose();
    super.dispose();
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
      // BUG FIX: Location failure never blocks checkout. Allow manual address entry.
      debugPrint('Location load error: $e');
      if (mounted) {
        setState(() {
          _useManualAddress = true;
          _address = 'Location unavailable - please enter your address manually';
        });
      }
    }
  }

  /// Validate and apply a promo code. Checks against Firestore promotions
  /// for eligibility, then sets the local state so the pricing recalculation
  /// picks up the promo discount.
  Future<void> _applyPromoCode() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) {
      setState(() { _promoError = 'Enter a promo code'; });
      return;
    }
    setState(() { _promoLoading = true; _promoError = null; });

    try {
      // Fetch active promotions and find matching code
      final snap = await _engageApi.promotions().first;
      final match = snap.docs.where((d) {
        final data = d.data();
        return (data['code'] ?? '').toString().toUpperCase() == code.toUpperCase();
      });

      if (match.isEmpty) {
        setState(() { _promoError = 'Invalid promo code'; _promoLoading = false; });
        return;
      }

      final promo = Promotion.fromMap(match.first.id, match.first.data());
      final subtotal = widget.cycles * widget.pricePerKg;

      // Check eligibility locally (mirrors server-side checks)
      if (promo.status != 'Active') {
        setState(() { _promoError = 'This promo is no longer active'; _promoLoading = false; });
        return;
      }
      if (promo.minimumOrderAmount > 0 && subtotal < promo.minimumOrderAmount) {
        setState(() { _promoError = 'Minimum transaction: ₱${promo.minimumOrderAmount.toStringAsFixed(0)}'; _promoLoading = false; });
        return;
      }
      if (promo.startDate != null && DateTime.now().isBefore(promo.startDate!)) {
        setState(() { _promoError = 'This promo is not yet active'; _promoLoading = false; });
        return;
      }
      if (promo.endDate != null && DateTime.now().isAfter(promo.endDate!)) {
        setState(() { _promoError = 'This promo has expired'; _promoLoading = false; });
        return;
      }

      setState(() { _appliedPromo = promo; _promoLoading = false; _promoError = null; });
    } catch (e) {
      setState(() { _promoError = 'Failed to validate promo'; _promoLoading = false; });
    }
  }

  void _removePromo() {
    setState(() { _appliedPromo = null; _promoController.clear(); _promoError = null; });
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
    final effectiveDeliveryFee = _deliveryMethod == 'Pickup' ? _deliveryFee : 0.0;

    // Use EngagementPricingEngine for consistent pricing
    final pricing = EngagementPricingEngine.calculate(
      actualWeight: widget.weight,
      pricing: ServicePricing(
        id: widget.serviceId,
        name: widget.serviceName,
        pricePerLoad: widget.pricePerKg,
      ),
      deliveryFee: effectiveDeliveryFee,
      soapTotal: widget.soapTotal,
      membership: _membershipPlan,
      promo: _appliedPromo,
    );

    final promoDiscount = pricing.promoDiscount;
    final membershipDiscount = pricing.membershipDiscount;
    final total = pricing.total;

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

    // BUG FIX: Build and persist delivery address
    AddressModel? deliveryAddress;
    if (_deliveryMethod == 'Pickup') {
      final street = _useManualAddress
          ? _manualStreetController.text.trim()
          : _address;
      final barangay = _useManualAddress
          ? _manualBarangayController.text.trim()
          : '';
      final city = _useManualAddress
          ? _manualCityController.text.trim()
          : '';
      // Additive snapshot: carry the customer's structured profile components
      // (from Location Setup) onto the order without altering existing logic.
      final profileAddress = user.address;
      deliveryAddress = AddressModel(
        street: street,
        barangay: barangay,
        city: city,
        latitude: _latitude,
        longitude: _longitude,
        houseUnit: profileAddress?.houseUnit ?? '',
        province: profileAddress?.province ?? '',
        postalCode: profileAddress?.postalCode ?? '',
        formattedAddress: profileAddress?.fullAddress ?? '',
      );
    }

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
      deliveryAddress: deliveryAddress,
      customerName: user.name,
      customerPhone: user.phone,
      requestedPromoCode: _appliedPromo?.code,
      promoDiscount: promoDiscount > 0 ? promoDiscount : null,
      membershipDiscount: membershipDiscount > 0 ? membershipDiscount : null,
      pricingBreakdown: pricing.toMap(),
    );

    setState(() => _isLoading = false);

    if (orderId != null && mounted) {
      Navigator.pushNamed(
        context,
        '/customer/payment',
        arguments: {
          'orderId': orderId,
          'amount': total < 0 ? 0 : total,
          'serviceName': widget.serviceName,
          'weight': widget.weight,
          'cycles': widget.cycles,
          'deliveryFee': effectiveDeliveryFee,
          'subtotal': subtotal,
          'selectedSoaps': widget.selectedSoaps,
          'soapTotal': widget.soapTotal,
          'deliveryMethod': _deliveryMethod,
          'promoDiscount': promoDiscount > 0 ? promoDiscount : null,
          'promoCode': _appliedPromo?.code,
          'membershipDiscount': membershipDiscount > 0 ? membershipDiscount : null,
        },
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create transaction. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = widget.cycles * widget.pricePerKg;
    final effectiveDeliveryFee = _deliveryMethod == 'Pickup' ? _deliveryFee : 0.0;

    // Use EngagementPricingEngine for consistent pricing
    final pricing = EngagementPricingEngine.calculate(
      actualWeight: widget.weight,
      pricing: ServicePricing(
        id: widget.serviceId,
        name: widget.serviceName,
        pricePerLoad: widget.pricePerKg,
      ),
      deliveryFee: effectiveDeliveryFee,
      soapTotal: widget.soapTotal,
      membership: _membershipPlan,
      promo: _appliedPromo,
    );

    final promoDiscount = pricing.promoDiscount;
    final membershipDiscount = pricing.membershipDiscount;
    _membershipDiscount = membershipDiscount;
    final total = pricing.total;

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
                            'Transaction Summary',
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
                  // ── Promo Code ──
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Promo Code',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_appliedPromo != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _appliedPromo!.code,
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                                        ),
                                        Text(
                                          _appliedPromo!.type == 'fixed'
                                              ? '₱${_appliedPromo!.value.toStringAsFixed(0)} off'
                                              : '${_appliedPromo!.value.toStringAsFixed(0)}% off',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _removePromo,
                                    child: const Text('Remove', style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _promoController,
                                    decoration: InputDecoration(
                                      hintText: 'Enter promo code',
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                      errorText: _promoError,
                                    ),
                                    textCapitalization: TextCapitalization.characters,
                                    onSubmitted: (_) => _applyPromoCode(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _promoLoading ? null : _applyPromoCode,
                                  child: _promoLoading
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Text('Apply'),
                                ),
                              ],
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
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Pickup Location',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_latitude != 0 || _useManualAddress)
                                  TextButton(
                                    onPressed: () => setState(() {
                                      _useManualAddress = !_useManualAddress;
                                    }),
                                    child: Text(
                                      _useManualAddress
                                          ? 'Use GPS'
                                          : 'Enter manually',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (!_useManualAddress) ...[
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
                                              _address != 'Unable to get address' &&
                                              !_address.contains('unavailable')
                                          ? _address
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
                            ] else ...[
                              // Manual address entry fields
                              TextField(
                                controller: _manualStreetController,
                                decoration: const InputDecoration(
                                  labelText: 'Street Address',
                                  hintText: 'e.g. 123 Main St, Sabalo',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _manualBarangayController,
                                decoration: const InputDecoration(
                                  labelText: 'Barangay',
                                  hintText: 'e.g. Dagat-Dagatan',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _manualCityController,
                                decoration: const InputDecoration(
                                  labelText: 'City',
                                  hintText: 'e.g. Caloocan City',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Please enter your complete address for pickup.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
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
                  // Discount & Total
                  Card(
                    color: const Color(0xFF1565C0).withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (promoDiscount > 0)
                            _buildSummaryRow(
                              'Promo Discount (${_appliedPromo!.code})',
                              '-${CurrencyHelper.formatSimple(promoDiscount)}',
                            ),
                          if (membershipDiscount > 0)
                            _buildSummaryRow(
                              'Membership Discount (${_membershipPlan!.name})',
                              '-${CurrencyHelper.formatSimple(membershipDiscount)}',
                            ),
                          if (promoDiscount > 0 || membershipDiscount > 0) const Divider(),
                          Row(
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
                                CurrencyHelper.formatSimple(total < 0 ? 0 : total),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
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
                  CustomButton(
                    text: 'Place Transaction & Proceed to Payment',
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
