import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/service_model.dart';

class ServiceProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<ServiceModel> _services = [];
  bool _isLoading = false;
  String? _error;

  /// Fallback local services used when Firestore is empty or unavailable
  final List<ServiceModel> _localServices = [
    ServiceModel(
      id: 'local_wash_only',
      name: 'Wash Only',
      description: 'Machine washing service only',
      pricePerKg: 70.0,
      type: 'Wash Only',
      estimatedMinutes: 45,
      maxKgPerCycle: 8.0,
      isActive: true,
      order: 1,
    ),
    ServiceModel(
      id: 'local_dry_only',
      name: 'Dry Only',
      description: 'Machine drying service only',
      pricePerKg: 70.0,
      type: 'Dry Only',
      estimatedMinutes: 30,
      maxKgPerCycle: 8.0,
      isActive: true,
      order: 2,
    ),
    ServiceModel(
      id: 'local_wash_dry',
      name: 'Wash and Dry',
      description: 'Complete wash and dry service',
      pricePerKg: 135.0,
      type: 'Wash and Dry',
      estimatedMinutes: 90,
      maxKgPerCycle: 8.0,
      isActive: true,
      order: 3,
    ),
  ];

  List<ServiceModel> get services => _services;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Stream<List<ServiceModel>> streamServices() {
    return _firestore
        .collection('services')
        .orderBy('order')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => ServiceModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  Future<List<ServiceModel>> loadServices() async {
    _isLoading = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('services')
          .orderBy('order')
          .get();
      final firestoreServices = snapshot.docs
          .map((doc) => ServiceModel.fromMap(doc.data(), doc.id))
          .toList();

      // Use Firestore services if available, otherwise use local fallback
      _services = firestoreServices.isNotEmpty
          ? firestoreServices
          : _localServices;
      _isLoading = false;
      notifyListeners();
      return _services;
    } catch (e) {
      // If Firestore fails, use local fallback services
      _services = _localServices;
      _error = null; // Clear error since we have fallback services
      _isLoading = false;
      notifyListeners();
      return _services;
    }
  }

  ServiceModel? getServiceById(String id) {
    try {
      return _services.firstWhere((s) => s.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> seedDefaultServices() async {
    final snapshot = await _firestore.collection('services').get();
    if (snapshot.docs.isNotEmpty) return;

    final services = [
      {
        'name': 'Wash Only',
        'description': 'Machine washing service only',
        'pricePerKg': 70.0,
        'pricePerItem': 0,
        'type': 'Wash Only',
        'estimatedMinutes': 45,
        'maxKgPerCycle': 8.0,
        'isActive': true,
        'order': 1,
      },
      {
        'name': 'Dry Only',
        'description': 'Machine drying service only',
        'pricePerKg': 70.0,
        'pricePerItem': 0,
        'type': 'Dry Only',
        'estimatedMinutes': 30,
        'maxKgPerCycle': 8.0,
        'isActive': true,
        'order': 2,
      },
      {
        'name': 'Wash and Dry',
        'description': 'Complete wash and dry service',
        'pricePerKg': 135.0,
        'pricePerItem': 0,
        'type': 'Wash and Dry',
        'estimatedMinutes': 90,
        'maxKgPerCycle': 8.0,
        'isActive': true,
        'order': 3,
      },
    ];

    final batch = _firestore.batch();
    for (final service in services) {
      final docRef = _firestore.collection('services').doc();
      batch.set(docRef, service);
    }
    await batch.commit();
  }
}
