class PaymentValidationEngine {
  /// Validate GCash reference number format
  static bool isValidReferenceNumber(String reference) {
    // GCash reference format: 13-digit number or alphanumeric
    final cleanRef = reference.replaceAll(' ', '');
    if (cleanRef.length < 10) return false;
    return RegExp(r'^[A-Za-z0-9]+$').hasMatch(cleanRef);
  }

  /// Validate payment amount against order total
  static bool isValidPaymentAmount(
    double paidAmount,
    double requiredAmount, {
    double tolerance = 0.50,
  }) {
    return (paidAmount - requiredAmount).abs() <= tolerance;
  }

  /// Check if receipt image is valid (basic checks)
  static bool isValidReceiptImage(String imageUrl) {
    return imageUrl.isNotEmpty &&
        (imageUrl.endsWith('.jpg') ||
            imageUrl.endsWith('.jpeg') ||
            imageUrl.endsWith('.png') ||
            imageUrl.endsWith('.JPG') ||
            imageUrl.endsWith('.PNG'));
  }

  /// Get payment status validation
  static Map<String, dynamic> validatePayment({
    required String referenceNumber,
    required double amount,
    required double orderTotal,
    String? receiptImageUrl,
  }) {
    final errors = <String>[];

    if (!isValidReferenceNumber(referenceNumber)) {
      errors.add('Invalid reference number format');
    }

    if (!isValidPaymentAmount(amount, orderTotal)) {
      errors.add('Payment amount does not match order total');
    }

    if (receiptImageUrl != null && !isValidReceiptImage(receiptImageUrl)) {
      errors.add('Invalid receipt image format');
    }

    return {
      'isValid': errors.isEmpty,
      'errors': errors,
      'referenceValid': isValidReferenceNumber(referenceNumber),
      'amountValid': isValidPaymentAmount(amount, orderTotal),
    };
  }

  /// Generate validation summary for admin
  static Map<String, dynamic> generateValidationSummary({
    required String referenceNumber,
    required double amount,
    required double orderTotal,
    required DateTime paymentDate,
    required bool hasReceiptImage,
  }) {
    final validation = validatePayment(
      referenceNumber: referenceNumber,
      amount: amount,
      orderTotal: orderTotal,
    );

    return {
      'validationResult': validation,
      'paymentDate': paymentDate.toIso8601String(),
      'hasReceipt': hasReceiptImage,
      'flagsForReview': !validation['isValid'] || amount < orderTotal,
    };
  }
}
