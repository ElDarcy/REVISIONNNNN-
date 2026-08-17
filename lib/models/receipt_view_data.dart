import 'order_load_model.dart';

/// Display-only receipt data assembled from the existing order/load records.
/// It is never persisted, so receipt rendering cannot diverge from operations.
class ReceiptViewData {
  final String transactionNumber;
  final DateTime createdAt;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;
  final String serviceType;
  final double weight;
  final double subtotal;
  final double? soapTotal;
  final List<Map<String, dynamic>>? selectedSoaps;
  final double total;
  final String paymentMethod;
  final String paymentMethodLabel;
  final String collectionMethodLabel;
  final String paymentStatus;
  final String status;
  final String displayStatus;
  final String assignedStaffName;
  final List<OrderLoadModel> loads;
  final String trackingUrl;

  const ReceiptViewData({
    required this.transactionNumber,
    required this.createdAt,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    required this.serviceType,
    required this.weight,
    required this.subtotal,
    this.soapTotal,
    this.selectedSoaps,
    required this.total,
    required this.paymentMethod,
    required this.paymentMethodLabel,
    required this.collectionMethodLabel,
    required this.paymentStatus,
    required this.status,
    required this.displayStatus,
    required this.assignedStaffName,
    required this.loads,
    required this.trackingUrl,
  });
}
