import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/brand.dart';
import '../../../core/widgets/location_pin_card.dart';
import '../../../core/widgets/onboarding_scaffold.dart';
import '../../../core/widgets/status_banner.dart';
import '../../../engines/distance_engine.dart';
import '../../../engines/service_area_engine.dart';
import '../../../models/address_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/service_provider.dart';
import '../../../services/location_service.dart';
import '../../../services/navigation_service.dart';

/// Customer delivery location onboarding / edit screen.
///
/// Enforces the delivery-location requirements BEFORE anything is saved:
/// complete address (House/Unit + Street, Barangay, City, Province) AND
/// usable coordinates AND within the 15 km service area. The customer must
/// explicitly verify the resolved location; the resolved coordinates (never
/// the text address) drive the service-area check. Google Maps is used ONLY
/// for visual confirmation.
///
/// Location data is written to `users/{uid}` exclusively when the customer
/// explicitly completes or edits this screen.
class LocationSetupScreen extends StatefulWidget {
  // Register flow (Step 2) — provided during email registration.
  final String? registerName;
  final String? registerEmail;
  final String? registerPassword;
  final String? registerPhone;
  // Edit mode — prefill with the customer's existing location.
  final AddressModel? initialAddress;
  // True when opened from the Profile screen (pop back after saving).
  final bool fromProfile;

  const LocationSetupScreen({
    super.key,
    this.registerName,
    this.registerEmail,
    this.registerPassword,
    this.registerPhone,
    this.initialAddress,
    this.fromProfile = false,
  });

  bool get isRegisterFlow =>
      registerName != null && registerEmail != null && registerPassword != null;

  @override
  State<LocationSetupScreen> createState() => _LocationSetupScreenState();
}

class _LocationSetupScreenState extends State<LocationSetupScreen> {
  final LocationService _locationService = LocationService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _houseUnit;
  late final TextEditingController _street;
  late final TextEditingController _barangay;
  late final TextEditingController _city;
  late final TextEditingController _province;
  late final TextEditingController _postalCode;

  bool _isResolving = false;
  bool _isSaving = false;
  bool _isGettingGps = false;
  String? _statusMessage;
  BannerTone? _statusTone;

  // Resolved coordinates from GPS or forward geocoding.
  double? _lat;
  double? _lng;
  double? _distanceKm;
  bool? _inServiceArea;
  String _resolvedSnapshot = '';

  // Ambiguous geocoding candidates awaiting explicit selection.
  List<Map<String, double>> _candidates = const [];

  @override
  void initState() {
    super.initState();
    final a = widget.initialAddress;
    _houseUnit = TextEditingController(text: a?.houseUnit ?? '');
    _street = TextEditingController(text: a?.street ?? '');
    _barangay = TextEditingController(text: a?.barangay ?? '');
    _city = TextEditingController(text: a?.city ?? '');
    _province = TextEditingController(text: a?.province ?? '');
    _postalCode = TextEditingController(text: a?.postalCode ?? '');
    if (a != null && LocationService.isValidCoordinate(a.latitude, a.longitude)) {
      _lat = a.latitude;
      _lng = a.longitude;
      _evaluateServiceArea(a.latitude, a.longitude);
      _resolvedSnapshot = _currentAddress();
    }
  }

  @override
  void dispose() {
    _houseUnit.dispose();
    _street.dispose();
    _barangay.dispose();
    _city.dispose();
    _province.dispose();
    _postalCode.dispose();
    super.dispose();
  }

  String _currentAddress() {
    return [
      _houseUnit.text.trim(),
      _street.text.trim(),
      _barangay.text.trim(),
      _city.text.trim(),
      _province.text.trim(),
      _postalCode.text.trim(),
    ].join('|');
  }

  void _setStatus(String message, BannerTone tone) {
    setState(() {
      _statusMessage = message;
      _statusTone = tone;
    });
  }

  void _clearStatus() {
    if (_statusMessage != null) {
      setState(() {
        _statusMessage = null;
        _statusTone = null;
      });
    }
  }

  void _onFieldChanged(String _) {
    // If the customer edits fields after resolving, the resolved location is
    // no longer valid and must be re-checked — never silently reused.
    if (_resolvedSnapshot.isNotEmpty && _currentAddress() != _resolvedSnapshot) {
      setState(() {
        _lat = null;
        _lng = null;
        _distanceKm = null;
        _inServiceArea = null;
        _resolvedSnapshot = '';
        _candidates = const [];
      });
    }
  }

  List<String> _requiredFields() {
    final missing = <String>[];
    if (_houseUnit.text.trim().isEmpty && _street.text.trim().isEmpty) {
      missing.add('House/Unit or Street');
    }
    if (_barangay.text.trim().isEmpty) missing.add('Barangay');
    if (_city.text.trim().isEmpty) missing.add('City/Municipality');
    if (_province.text.trim().isEmpty) missing.add('Province');
    return missing;
  }

  String _fullAddressForLookup() {
    return [
      _houseUnit.text.trim(),
      _street.text.trim(),
      _barangay.text.trim(),
      _city.text.trim(),
      _province.text.trim(),
      _postalCode.text.trim(),
    ]
        .where((part) => part.isNotEmpty)
        .join(', ');
  }

  Future<void> _useCurrentLocation() async {
    _clearStatus();
    setState(() => _isGettingGps = true);
    try {
      final location = await _locationService.getLocationDetails();
      final lat = location['latitude'] as double;
      final lng = location['longitude'] as double;
      // Best-effort reverse-geocode fills the form fields.
      final components = await _locationService.getAddressComponents(lat, lng);

      if (!mounted) return;
      setState(() {
        if (_street.text.trim().isEmpty) {
          _street.text = components['street'] ?? '';
        }
        if (_barangay.text.trim().isEmpty) {
          _barangay.text = components['barangay'] ?? '';
        }
        if (_city.text.trim().isEmpty) {
          _city.text = components['city'] ?? '';
        }
        if (_province.text.trim().isEmpty) {
          _province.text = components['province'] ?? '';
        }
        if (_postalCode.text.trim().isEmpty) {
          _postalCode.text = components['postalCode'] ?? '';
        }
        _lat = lat;
        _lng = lng;
        _evaluateServiceArea(lat, lng);
        _resolvedSnapshot = _currentAddress();
        _candidates = const [];
        _isGettingGps = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGettingGps = false);
      // GPS is optional: permission denial or GPS failure must never block the
      // customer from entering their address manually.
      _setStatus(
        'Could not get your current location. You can still enter your '
        'address manually — or tap Use My Current Location to retry.',
        BannerTone.warning,
      );
    }
  }

  void _evaluateServiceArea(double lat, double lng) {
    final distance = DistanceEngine.distanceFromShop(lat, lng);
    _distanceKm = distance;
    _inServiceArea = ServiceAreaEngine.isInServiceArea(lat, lng);
  }

  Future<void> _checkAddress() async {
    final missing = _requiredFields();
    if (missing.isNotEmpty) {
      _setStatus(
        'Please fill in the required fields first: ${missing.join(', ')}.',
        BannerTone.error,
      );
      return;
    }

    _clearStatus();
    setState(() {
      _isResolving = true;
      _candidates = const [];
    });

    final candidates =
        await _locationService.getCoordinatesFromAddress(_fullAddressForLookup());

    if (!mounted) return;
    setState(() => _isResolving = false);

    if (candidates.isEmpty) {
      _setStatus(
        'We could not find that address. Please check the spelling and try '
        'again, or use your current location.',
        BannerTone.error,
      );
      return;
    }

    if (candidates.length == 1) {
      _selectCandidate(candidates.first);
    } else {
      // Ambiguous result — the first match is never silently chosen. Show all
      // candidates with their distance from the shop for explicit selection.
      setState(() => _candidates = candidates);
      _setStatus(
        'Multiple locations matched. Please choose the correct one.',
        BannerTone.info,
      );
    }
  }

  void _selectCandidate(Map<String, double> candidate) {
    final lat = candidate['latitude']!;
    final lng = candidate['longitude']!;
    setState(() {
      _lat = lat;
      _lng = lng;
      _candidates = const [];
      _evaluateServiceArea(lat, lng);
      _resolvedSnapshot = _currentAddress();
    });
    if (_inServiceArea == false) {
      _setStatus(
        'This address is outside our 15 km delivery area '
        '(${_distanceKm!.toStringAsFixed(1)} km from the shop).',
        BannerTone.error,
      );
    }
  }

  Future<void> _verifyOnMap() async {
    if (_lat == null || _lng == null) return;
    await NavigationService.openMap(
      latitude: _lat!,
      longitude: _lng!,
      label: _fullAddressForLookup(),
    );
  }

  Future<void> _save() async {
    if (_lat == null || _lng == null) return;
    if (_inServiceArea != true) return;

    final address = AddressModel(
      houseUnit: _houseUnit.text.trim(),
      street: _street.text.trim(),
      barangay: _barangay.text.trim(),
      city: _city.text.trim(),
      province: _province.text.trim(),
      postalCode: _postalCode.text.trim(),
      latitude: _lat!,
      longitude: _lng!,
      formattedAddress: _fullAddressForLookup(),
    );

    setState(() => _isSaving = true);

    final authProvider = context.read<AuthProvider>();
    bool success;

    if (widget.isRegisterFlow) {
      success = await authProvider.register(
        name: widget.registerName!,
        email: widget.registerEmail!,
        password: widget.registerPassword!,
        phone: widget.registerPhone ?? '',
        addressModel: address,
      );
    } else {
      success = await authProvider.updateCustomerLocation(address);
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (!success) {
      _setStatus(
        authProvider.error ?? 'Something went wrong. Please try again.',
        BannerTone.error,
      );
      return;
    }

    if (widget.isRegisterFlow) {
      await context.read<ServiceProvider>().loadServices();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/customer/home',
        (route) => false,
      );
    } else if (widget.fromProfile) {
      if (!mounted) return;
      Navigator.of(context).pop();
    } else {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/customer/home',
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRegister = widget.isRegisterFlow;

    return Scaffold(
      appBar: widget.fromProfile
          ? AppBar(title: const Text('Delivery Location'))
          : null,
      backgroundColor: BrandColors.background,
      body: OnboardingScaffold(
        resizeToAvoidBottomInset: true,
        header: isRegister
            ? const _RegisterStepHeader()
            : null,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isRegister
                    ? 'Where do we deliver?'
                    : 'Where should we pick up and deliver your laundry?',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSizes.spaceSm),
              Text(
                'We use this address so our delivery staff can find you for '
                'pickup and delivery. Enter it manually, use your current '
                'location, or both — then verify it before saving.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSizes.spaceLg),

              if (_statusMessage != null) ...[
                StatusBanner(tone: _statusTone ?? BannerTone.info, message: _statusMessage!),
                const SizedBox(height: AppSizes.spaceMd),
              ],

              _TextField(
                controller: _houseUnit,
                label: 'House / Unit / Building / Lot',
                hint: 'e.g. Blk 5 Lot 12',
                icon: Icons.home_outlined,
                onChanged: _onFieldChanged,
              ),
              const SizedBox(height: AppSizes.spaceMd),
              _TextField(
                controller: _street,
                label: 'Street',
                hint: 'e.g. Mabini Street',
                icon: Icons.signpost_outlined,
                onChanged: _onFieldChanged,
              ),
              const SizedBox(height: AppSizes.spaceMd),
              _TextField(
                controller: _barangay,
                label: 'Barangay',
                hint: 'e.g. San Isidro',
                icon: Icons.map_outlined,
                onChanged: _onFieldChanged,
              ),
              const SizedBox(height: AppSizes.spaceMd),
              _TextField(
                controller: _city,
                label: 'City / Municipality',
                hint: 'e.g. Meycauayan',
                icon: Icons.location_city_outlined,
                onChanged: _onFieldChanged,
              ),
              const SizedBox(height: AppSizes.spaceMd),
              _TextField(
                controller: _province,
                label: 'Province',
                hint: 'e.g. Bulacan',
                icon: Icons.flag_outlined,
                onChanged: _onFieldChanged,
              ),
              const SizedBox(height: AppSizes.spaceMd),
              _TextField(
                controller: _postalCode,
                label: 'Postal Code (if applicable)',
                hint: 'e.g. 3020',
                icon: Icons.numbers_outlined,
                keyboardType: TextInputType.number,
                onChanged: _onFieldChanged,
              ),
              const SizedBox(height: AppSizes.spaceXl),

              OutlinedButton.icon(
                onPressed: _isGettingGps ? null : _useCurrentLocation,
                icon: _isGettingGps
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(
                  _isGettingGps ? 'Getting location…' : 'Use My Current Location',
                ),
              ),
              const SizedBox(height: AppSizes.spaceSm + 4),
              FilledButton.icon(
                onPressed: _isResolving ? null : _checkAddress,
                icon: _isResolving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search),
                label: Text(_isResolving ? 'Checking address…' : 'Check My Address'),
              ),
              const SizedBox(height: AppSizes.spaceMd),

              if (_candidates.isNotEmpty) _buildCandidatePicker(),
              if (_lat != null && _lng != null && _inServiceArea != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSizes.spaceMd),
                  child: LocationPinCard(
                    formattedAddress: _fullAddressForLookup(),
                    latitude: _lat!,
                    longitude: _lng!,
                    distanceKm: _distanceKm!,
                    inServiceArea: _inServiceArea!,
                    onVerifyOnMap: _verifyOnMap,
                    onConfirm: _save,
                    isConfirming: _isSaving,
                    confirmLabel: isRegister ? 'Create Account' : 'Confirm & Save',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCandidatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose the correct location:',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: BrandColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSizes.spaceSm),
        ..._candidates.map((candidate) {
          final distance = DistanceEngine.distanceFromShop(
            candidate['latitude']!,
            candidate['longitude']!,
          );
          final inArea = ServiceAreaEngine.isInServiceArea(
            candidate['latitude']!,
            candidate['longitude']!,
          );
          return Card(
            margin: const EdgeInsets.only(bottom: AppSizes.spaceSm),
            child: ListTile(
              leading: Icon(
                inArea ? Icons.place_outlined : Icons.location_off_outlined,
                color: inArea ? BrandColors.navy : BrandColors.error,
              ),
              title: Text(
                '${candidate['latitude']!.toStringAsFixed(4)}, '
                '${candidate['longitude']!.toStringAsFixed(4)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              subtitle: Text(
                '${distance.toStringAsFixed(1)} km from shop'
                '${inArea ? '' : ' · outside area'}',
                style: TextStyle(
                  color: inArea ? BrandColors.textSecondary : BrandColors.error,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _selectCandidate(candidate),
            ),
          );
        }),
        const SizedBox(height: AppSizes.spaceSm),
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final ValueChanged<String> onChanged;

  const _TextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onChanged,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.words,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }
}

class _RegisterStepHeader extends StatelessWidget {
  const _RegisterStepHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          BrandAssets.logo,
          height: 72,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.local_laundry_service,
            size: 72,
            color: BrandColors.navy,
          ),
        ),
        const SizedBox(height: AppSizes.spaceMd),
        Text(
          'Step 2 of 2 · Delivery Location',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: BrandColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}