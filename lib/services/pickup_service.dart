import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

/// Service for generating and verifying pickup tokens/OTP codes.
///
/// When a customer chooses "Personal Pickup":
/// 1. Generate an opaque pickup token
/// 2. Generate a 6-digit numeric OTP code as backup
/// 3. Store in `pickupTokens/{tokenId}` collection
/// 4. Staff scans QR (containing the token) or enters the 6-digit code
/// 5. One-time use with expiration
class PickupService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final Uuid _uuid = const Uuid();
  static final Random _secureRandom = Random.secure();

  /// Generate pickup credentials for an order.
  /// Returns a map with {token, code, tokenId, expiresAt}.
  static Future<Map<String, dynamic>> generatePickupCredentials({
    required String orderId,
    Duration expiration = const Duration(days: 2),
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(expiration);

    // Generate opaque token (URL-safe, no sensitive info embedded)
    final rawToken = _generateSecureToken();

    // Generate 6-digit OTP code
    final code = _generateOtpCode();

    final tokenId = _uuid.v4();

    // Store in pickupTokens collection
    await _firestore.collection('pickupTokens').doc(tokenId).set({
      'orderId': orderId,
      'token': rawToken,
      'code': code,
      'used': false,
      'createdAt': Timestamp.now(),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    // Update order with pickup fields
    await _firestore.collection('orders').doc(orderId).update({
      'pickupToken': rawToken,
      'pickupCode': code,
      'pickupExpiresAt': Timestamp.fromDate(expiresAt),
    });

    return {
      'token': rawToken,
      'code': code,
      'tokenId': tokenId,
      'expiresAt': expiresAt,
    };
  }

  /// Verify a pickup via QR token or OTP code.
  /// Returns {success, message, orderId?}.
  static Future<Map<String, dynamic>> verifyPickup({
    String? token,
    String? code,
    required String staffId,
  }) async {
    if ((token == null || token.isEmpty) && (code == null || code.isEmpty)) {
      return {'success': false, 'message': 'No token or code provided.'};
    }

    try {
      if (token != null && token.isNotEmpty) {
        return await _verifyByToken(token, staffId);
      }
      if (code != null && code.isNotEmpty) {
        return await _verifyByCode(code, staffId);
      }
      return {'success': false, 'message': 'Invalid verification data.'};
    } catch (e) {
      return {'success': false, 'message': 'Verification failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> _verifyByToken(
    String rawToken,
    String staffId,
  ) async {
    final tokenSnap = await _firestore
        .collection('pickupTokens')
        .where('token', isEqualTo: rawToken)
        .limit(1)
        .get();

    if (tokenSnap.docs.isEmpty) {
      return {'success': false, 'message': 'Invalid pickup QR code.'};
    }

    final tokenDoc = tokenSnap.docs.first;
    final tokenData = tokenDoc.data();

    return await _processVerification(tokenDoc.id, tokenData, staffId);
  }

  static Future<Map<String, dynamic>> _verifyByCode(
    String code,
    String staffId,
  ) async {
    final tokenSnap = await _firestore
        .collection('pickupTokens')
        .where('code', isEqualTo: code.trim())
        .limit(1)
        .get();

    if (tokenSnap.docs.isEmpty) {
      return {'success': false, 'message': 'Invalid pickup code.'};
    }

    final tokenDoc = tokenSnap.docs.first;
    final tokenData = tokenDoc.data();

    return await _processVerification(tokenDoc.id, tokenData, staffId);
  }

  static Future<Map<String, dynamic>> _processVerification(
    String tokenId,
    Map<String, dynamic> tokenData,
    String staffId,
  ) async {
    final orderId = tokenData['orderId'] as String?;
    if (orderId == null || orderId.isEmpty) {
      return {'success': false, 'message': 'Invalid token record.'};
    }

    final expiresAt = _parseTimestamp(tokenData['expiresAt']);
    if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
      return {
        'success': false,
        'message': 'This pickup code has expired. Please request a new one.',
      };
    }

    if (tokenData['used'] == true) {
      return {
        'success': false,
        'message': 'This pickup code has already been used.',
      };
    }

    final now = Timestamp.now();
    String? transactionNumber;
    String? customerName;

    await _firestore.runTransaction((transaction) async {
      final tokenRef = _firestore.collection('pickupTokens').doc(tokenId);
      final tokenSnap = await transaction.get(tokenRef);
      if (!tokenSnap.exists || tokenSnap.data()?['used'] == true) {
        throw Exception('Token already used');
      }

      final orderRef = _firestore.collection('orders').doc(orderId);
      final orderSnap = await transaction.get(orderRef);
      if (!orderSnap.exists)         throw Exception('Transaction not found');
      final orderData = orderSnap.data()!;

      transaction.update(tokenRef, {
        'used': true,
        'usedAt': now,
        'usedBy': staffId,
      });

      transaction.update(orderRef, {
        'status': 'Completed',
        'fulfillmentMethod': 'Personal Pickup',
        'pickupVerifiedAt': now,
        'pickupVerifiedBy': staffId,
        'completedAt': now,
        'updatedAt': now,
      });

      transactionNumber = orderData['transactionNumber'] as String?;
      customerName = orderData['customerName'] as String?;
    });

    return {
      'success': true,
      'message': 'Pickup verified successfully!',
      'orderId': orderId,
      'transactionNumber': transactionNumber,
      'customerName': customerName,
    };
  }

  /// Generate a URL-safe opaque token.
  static String _generateSecureToken() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final buffer = StringBuffer();
    for (var i = 0; i < 48; i++) {
      buffer.write(chars[_secureRandom.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  /// Generate a 6-digit numeric OTP code.
  static String _generateOtpCode() {
    final code = _secureRandom.nextInt(900000) + 100000;
    return code.toString();
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
