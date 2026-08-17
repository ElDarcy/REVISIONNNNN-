import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Loads only new Base64 weight proofs. Legacy URL evidence remains displayed
/// by the existing network-image fallback in the caller.
class TransactionProofService {
  TransactionProofService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<Uint8List?> loadImageBytes({
    required String proofId,
    required String orderId,
  }) async {
    final snapshot = await _firestore
        .collection('transaction_proofs')
        .doc(proofId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null || data['txn_id'] != orderId) {
      return null;
    }
    final imageBase64 = data['image_base64'] as String?;
    if (imageBase64 == null || imageBase64.isEmpty) return null;
    return Uint8List.fromList(base64Decode(imageBase64));
  }
}
