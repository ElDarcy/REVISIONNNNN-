/// Pure helpers for computing a laundry transaction's outstanding balance or
/// refund against the actual amount received from the customer.
///
/// The single admin gate is payment verification. The verified payment amount
/// becomes [amountPaid]. Once the verified weight reprice sets [finalAmount],
/// the difference between the two determines what is still owed by the
/// customer ([balanceDue]) or owed back to them ([refundAmount]). Keeping this
/// logic here (instead of inline in providers) makes it unit-testable and
/// guarantees the client and cloud function stay consistent.
class FinancialSettlementEngine {
  /// Balance the customer still owes:
  /// `max(0, finalAmount - amountPaid)`.
  static double balanceDue({
    required double finalAmount,
    required double amountPaid,
  }) {
    if (finalAmount <= 0) return 0;
    return (finalAmount - amountPaid).clamp(0, double.infinity).toDouble();
  }

  /// Overpayment owed back to the customer:
  /// `max(0, amountPaid - finalAmount)`.
  static double refundAmount({
    required double finalAmount,
    required double amountPaid,
  }) {
    if (finalAmount <= 0) return 0;
    return (amountPaid - finalAmount).clamp(0, double.infinity).toDouble();
  }

  /// True once the transaction is financially settled: nothing owed in either
  /// direction (or the total is not yet known).
  static bool isSettled({
    required double finalAmount,
    required double amountPaid,
    required bool balanceSettled,
    required bool refundSettled,
  }) {
    if (finalAmount <= 0) return true;
    final outstanding = balanceDue(finalAmount: finalAmount, amountPaid: amountPaid);
    final refund = refundAmount(finalAmount: finalAmount, amountPaid: amountPaid);
    if (outstanding > 0) return balanceSettled;
    if (refund > 0) return refundSettled;
    return true;
  }
}