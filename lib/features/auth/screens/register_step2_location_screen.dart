import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../services/location_service.dart';
import '../../../engines/distance_engine.dart';
import '../../../engines/service_area_engine.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/service_provider.dart';

class RegisterStep2LocationScreen extends StatefulWidget {
  final String name;
  final String email;
  final String password;
  final String phone;

  const RegisterStep2LocationScreen({
    super.key,
    required this.name,
    required this.email,
    required this.password,
    required this.phone,
  });

  @override
  State<RegisterStep2LocationScreen> createState() =>
      _RegisterStep2LocationScreenState();
}

class _RegisterStep2LocationScreenState
    extends State<RegisterStep2LocationScreen> {
  final LocationService _locationService = LocationService();
  bool _isGettingLocation = false;
  bool _locationObtained = false;
  double? _latitude;
  double? _longitude;
  String? _address;
  String? _distance;
  bool _inServiceArea = false;
  String? _error;

  Future<void> _getLocation() async {
    setState(() {
      _isGettingLocation = true;
      _error = null;
    });

    try {
      final location = await _locationService.getLocationDetails();
      final lat = location['latitude'] as double;
      final lng = location['longitude'] as double;
      final address = location['address'] as String;

      final distance = DistanceEngine.distanceFromShop(lat, lng);
      final inArea = ServiceAreaEngine.isInServiceArea(lat, lng);

      setState(() {
        _latitude = lat;
        _longitude = lng;
        _address = address;
        _distance = '${distance.toStringAsFixed(1)} km';
        _inServiceArea = inArea;
        _locationObtained = true;
        _isGettingLocation = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isGettingLocation = false;
      });
    }
  }

  Future<void> _register() async {
    if (!_locationObtained || !_inServiceArea) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.register(
      name: widget.name,
      email: widget.email,
      password: widget.password,
      phone: widget.phone,
      latitude: _latitude!,
      longitude: _longitude!,
      address: _address ?? '',
    );

    if (!mounted) return;

    if (success) {
      // Pre-load services from Firestore so they're ready when home screen renders
      await context.read<ServiceProvider>().loadServices();

      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(
        context,
        '/customer/home',
        (route) => false,
      );
    } else if (authProvider.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authProvider.error!),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Set Location')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Step 2 of 2',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: 1.0,
              backgroundColor: Colors.grey.shade200,
              color: const Color(0xFF1565C0),
            ),
            const SizedBox(height: 24),
            const Text(
              'Your Location',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'We need your location to check delivery availability',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),

            if (!_locationObtained && !_isGettingLocation) ...[
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 80,
                      color: Color(0xFF1565C0),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Enable GPS to check if we can deliver to your area',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    CustomButton(
                      text: 'Get My Location',
                      icon: Icons.my_location,
                      onPressed: _getLocation,
                    ),
                  ],
                ),
              ),
            ],

            if (_isGettingLocation)
              const LoadingWidget(message: 'Getting your location...'),

            if (_locationObtained) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _inServiceArea
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _inServiceArea ? Colors.green : Colors.red,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _inServiceArea ? Icons.check_circle : Icons.cancel,
                      size: 60,
                      color: _inServiceArea ? Colors.green : Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _inServiceArea
                          ? 'We deliver to your area!'
                          : 'Outside delivery area',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _inServiceArea ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Distance from shop: $_distance'),
                    if (_address != null) ...[
                      const SizedBox(height: 4),
                      Text(_address!, textAlign: TextAlign.center),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              CustomButton(
                text: 'Create Account',
                isLoading: authProvider.isLoading,
                onPressed: _inServiceArea ? _register : null,
              ),
            ],

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              CustomButton(
                text: 'Try Again',
                isOutlined: true,
                onPressed: _getLocation,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
