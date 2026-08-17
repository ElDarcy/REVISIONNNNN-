import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Centralized engine for managing soap inventory deductions.
/// Ensures atomic updates and prevents double deductions.
class InventoryEngine {
  /// Deducts soap quantities for an order within a Firestore transaction.
  /// 
  /// Prerequisites:
  /// - Order must have a 'Verified' payment status (business rule).
  /// - Order should have 'selectedSoaps' data.
  /// - 'soapDeducted' flag must be false.
  static Future<void> deductSoapsForOrder(
    Transaction transaction,
    DocumentReference orderRef,
    Map<String, dynamic> orderData,
    FirebaseFirestore firestore,
  ) async {
    final orderId = orderRef.id;
    final transactionNumber = orderData['transactionNumber'] ?? 'N/A';
    
    // 1. Double-deduction protection
    if (orderData['soapDeducted'] == true) {
      debugPrint('InventoryEngine: Soaps already deducted for $orderId');
      return;
    }

    final selectedSoaps = orderData['selectedSoaps'] as List<dynamic>?;
    
    // 2. Backward compatibility / No soap check
    if (selectedSoaps == null || selectedSoaps.isEmpty) {
      debugPrint('InventoryEngine: No soaps to deduct for $orderId');
      transaction.update(orderRef, {'soapDeducted': true});
      return;
    }

    debugPrint('InventoryEngine: Deducting soaps for $orderId ($transactionNumber)');

    // 3. Atomicity: Pre-fetch all required soap snapshots
    final soapSnaps = <String, DocumentSnapshot<Map<String, dynamic>>>{};
    for (final item in selectedSoaps) {
      final soapId = item['soapId'] as String;
      final soapRef = firestore.collection('soaps').doc(soapId);
      soapSnaps[soapId] = await transaction.get(soapRef);
    }

    // 4. Validate and Apply Deductions
    for (final item in selectedSoaps) {
      final soapId = item['soapId'] as String;
      final quantity = (item['quantity'] as num).toInt();
      final soapSnap = soapSnaps[soapId]!;

      if (!soapSnap.exists) {
        throw Exception('Soap $soapId not found in inventory');
      }

      final data = soapSnap.data()!;
      final currentStock = data['stockQuantity'] as int? ?? 0;
      final soapName = data['name'] ?? 'Unknown Soap';

      // Insufficient stock check (Atomicity: whole transaction fails if one fails)
      if (currentStock < quantity) {
        throw Exception('Insufficient stock for $soapName (Available: $currentStock, Requested: $quantity)');
      }

      final newStock = currentStock - quantity;
      
      // Update Soap Stock
      transaction.update(soapSnap.reference, {
        'stockQuantity': newStock,
        'stockStatus': newStock > 0 ? 'In Stock' : 'Out of Stock',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 5. Create Inventory Log entry
      final logRef = firestore.collection('inventoryLogs').doc();
      transaction.set(logRef, {
        'soapId': soapId,
        'soapName': soapName,
        'orderId': orderId,
        'transactionNumber': transactionNumber,
        'action': 'deduction',
        'quantity': quantity,
        'previousStock': currentStock,
        'newStock': newStock,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    // 6. Finalize Order state
    transaction.update(orderRef, {
      'soapDeducted': true,
      'inventoryDeductedAt': FieldValue.serverTimestamp(),
    });
  }
}
