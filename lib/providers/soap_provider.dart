import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/soap_model.dart';

class SoapProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  List<SoapModel> _soaps = [];
  bool _isLoading = false;
  String? _error;

  List<SoapModel> get soaps => _soaps;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Real-time stream of soaps from Firestore
  Stream<List<SoapModel>> streamSoaps() {
    return _firestore
        .collection('soaps')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => SoapModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  /// Load soaps from Firestore (single fetch)
  Future<List<SoapModel>> loadSoaps() async {
    _isLoading = true;
    notifyListeners();

    try {
      final snapshot = await _firestore
          .collection('soaps')
          .orderBy('name')
          .get();
      _soaps = snapshot.docs
          .map((doc) => SoapModel.fromMap(doc.data(), doc.id))
          .toList();
      _isLoading = false;
      _error = null;
      notifyListeners();
      return _soaps;
    } catch (e) {
      _error = 'Failed to load soaps from Firestore: $e';
      _soaps = [];
      _isLoading = false;
      notifyListeners();
      return _soaps;
    }
  }

  SoapModel? getSoapById(String id) {
    try {
      return _soaps.firstWhere((s) => s.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get only soaps that are in stock and active
  List<SoapModel> get availableSoaps =>
      _soaps.where((s) => s.isInStock && s.isActive).toList();

  Future<void> addSoap({
    required String name,
    String brand = '',
    String description = '',
    double price = 0,
    String unit = 'sachet',
    int stockQuantity = 0,
    String category = 'Detergent',
    String colorHex = '#1565C0',
    int order = 0,
  }) async {
    try {
      final docRef = _firestore.collection('soaps').doc();
      final soap = SoapModel(
        id: docRef.id,
        name: name,
        brand: brand,
        description: description,
        price: price,
        unit: unit,
        stockStatus: stockQuantity > 0 ? 'In Stock' : 'Out of Stock',
        stockQuantity: stockQuantity,
        category: category,
        colorHex: colorHex,
        isActive: true,
        order: order,
      );

      await docRef.set(soap.toMap());
      _soaps.add(soap);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateSoap(SoapModel soap) async {
    try {
      await _firestore.collection('soaps').doc(soap.id).update(soap.toMap());
      final index = _soaps.indexWhere((s) => s.id == soap.id);
      if (index != -1) {
        _soaps[index] = soap;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> toggleStockStatus(String soapId) async {
    try {
      final soap = getSoapById(soapId);
      if (soap == null) return;

      final newStatus = soap.stockStatus == 'In Stock'
          ? 'Out of Stock'
          : 'In Stock';
      await _firestore.collection('soaps').doc(soapId).update({
        'stockStatus': newStatus,
      });

      final updatedSoap = soap.copyWith(stockStatus: newStatus);
      final index = _soaps.indexWhere((s) => s.id == soapId);
      if (index != -1) {
        _soaps[index] = updatedSoap;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateStockQuantity(String soapId, int quantity) async {
    try {
      final soap = getSoapById(soapId);
      if (soap == null) return;

      final newStatus = quantity > 0 ? 'In Stock' : 'Out of Stock';
      await _firestore.collection('soaps').doc(soapId).update({
        'stockQuantity': quantity,
        'stockStatus': newStatus,
      });

      final updatedSoap = soap.copyWith(
        stockQuantity: quantity,
        stockStatus: newStatus,
      );
      final index = _soaps.indexWhere((s) => s.id == soapId);
      if (index != -1) {
        _soaps[index] = updatedSoap;
        notifyListeners();
      }
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> deleteSoap(String soapId) async {
    try {
      await _firestore.collection('soaps').doc(soapId).delete();
      _soaps.removeWhere((s) => s.id == soapId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Seed default soaps to Firestore (only if collection is empty).
  /// This provides initial data for new Firestore databases.
  Future<void> seedDefaultSoaps() async {
    try {
      final snapshot = await _firestore.collection('soaps').get();
      if (snapshot.docs.isNotEmpty) return;

      final defaultSoaps = [
        {
          'name': 'Downy Passion',
          'brand': 'Downy',
          'description': 'Fabric conditioner with lasting freshness',
          'price': 7.0,
          'unit': 'sachet',
          'stockStatus': 'In Stock',
          'stockQuantity': 100,
          'category': 'Fabric Conditioner',
          'colorHex': '#7B1FA2',
          'isActive': true,
          'imageUrl': null,
          'order': 1,
        },
        {
          'name': 'Downy Antibac',
          'brand': 'Downy',
          'description': 'Fabric conditioner with antibacterial protection',
          'price': 7.0,
          'unit': 'sachet',
          'stockStatus': 'In Stock',
          'stockQuantity': 100,
          'category': 'Fabric Conditioner',
          'colorHex': '#8E24AA',
          'isActive': true,
          'imageUrl': null,
          'order': 2,
        },
        {
          'name': 'Tide Original',
          'brand': 'Tide',
          'description': 'Premium laundry detergent',
          'price': 10.0,
          'unit': 'sachet',
          'stockStatus': 'In Stock',
          'stockQuantity': 100,
          'category': 'Detergent',
          'colorHex': '#E65100',
          'isActive': true,
          'imageUrl': null,
          'order': 3,
        },
        {
          'name': 'Tide with Downy',
          'brand': 'Tide',
          'description': 'Detergent with built-in fabric conditioner',
          'price': 12.0,
          'unit': 'sachet',
          'stockStatus': 'In Stock',
          'stockQuantity': 80,
          'category': 'Detergent',
          'colorHex': '#BF360C',
          'isActive': true,
          'imageUrl': null,
          'order': 4,
        },
        {
          'name': 'Ariel',
          'brand': 'Ariel',
          'description': 'Powerful stain removal detergent',
          'price': 10.0,
          'unit': 'sachet',
          'stockStatus': 'In Stock',
          'stockQuantity': 100,
          'category': 'Detergent',
          'colorHex': '#D32F2F',
          'isActive': true,
          'imageUrl': null,
          'order': 5,
        },
        {
          'name': 'Surf',
          'brand': 'Surf',
          'description': 'Affordable laundry detergent',
          'price': 8.0,
          'unit': 'sachet',
          'stockStatus': 'In Stock',
          'stockQuantity': 100,
          'category': 'Detergent',
          'colorHex': '#1565C0',
          'isActive': true,
          'imageUrl': null,
          'order': 6,
        },
        {
          'name': 'Zonrox',
          'brand': 'Zonrox',
          'description': 'Laundry bleach for whites',
          'price': 15.0,
          'unit': 'bottle',
          'stockStatus': 'In Stock',
          'stockQuantity': 50,
          'category': 'Bleach',
          'colorHex': '#2E7D32',
          'isActive': true,
          'imageUrl': null,
          'order': 7,
        },
        {
          'name': 'Mr. Muscle',
          'brand': 'Mr. Muscle',
          'description': 'Fabric conditioner',
          'price': 7.0,
          'unit': 'sachet',
          'stockStatus': 'In Stock',
          'stockQuantity': 100,
          'category': 'Fabric Conditioner',
          'colorHex': '#F9A825',
          'isActive': true,
          'imageUrl': null,
          'order': 8,
        },
        {
          'name': 'Perla',
          'brand': 'Perla',
          'description': 'Laundry bar soap for hand washing',
          'price': 8.0,
          'unit': 'bar',
          'stockStatus': 'In Stock',
          'stockQuantity': 60,
          'category': 'Laundry Soap',
          'colorHex': '#00ACC1',
          'isActive': true,
          'imageUrl': null,
          'order': 9,
        },
      ];

      final batch = _firestore.batch();
      final now = DateTime.now().toIso8601String();
      for (final soapData in defaultSoaps) {
        final docRef = _firestore.collection('soaps').doc();
        batch.set(docRef, {...soapData, 'id': docRef.id, 'createdAt': now});
      }
      await batch.commit();

      // Reload soaps after seeding
      await loadSoaps();
    } catch (e) {
      // Silently fail during seeding
    }
  }
}
