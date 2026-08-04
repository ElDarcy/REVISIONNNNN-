import 'package:intl/intl.dart';

class CurrencyHelper {
  static final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'en_PH',
    symbol: '₱',
  );

  static String format(double amount) {
    return _currencyFormat.format(amount);
  }

  static String formatSimple(double amount) {
    return '₱${amount.toStringAsFixed(2)}';
  }

  /// Format amount as whole peso (no decimal places)
  /// Example: ₱23.88 → ₱24
  static String formatWhole(double amount) {
    return '₱${amount.round()}';
  }

  static double parse(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  static double calculateTotal(
    double pricePerKg,
    double weight,
    double deliveryFee,
  ) {
    return (pricePerKg * weight) + deliveryFee;
  }

  static double calculateChange(double amountPaid, double total) {
    return amountPaid - total;
  }

  static String formatVAT(double amount) {
    final vat = amount * 0.12;
    return format(vat);
  }

  static String formatSubtotal(double amount) {
    final subtotal = amount / 1.12;
    return format(subtotal);
  }

  static String toWords(double amount) {
    if (amount == 0) return 'Zero Pesos';

    final numberFormatter = NumberFormat('#,##0.00');
    return '₱${numberFormatter.format(amount)}';
  }

  static bool isWithinBudget(double amount, double budget) {
    return amount <= budget;
  }
}
