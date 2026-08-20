import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single entry in the `deliveryQueue` collection.
///
/// The document ID is the `orderId` so each order can only have one entry
/// (duplicate prevention). Delivery staff act on these entries to start and
/// complete deliveries.
class DeliveryQueueEntry {
  final String orderId;
  final String? transactionNumber;
  final String? customerId;
  final String? customerName;
  final String? address;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final int priorityScore;
  final String status; // Pending Delivery | Out for Delivery | Completed | ...
  final String type; // pickup | delivery
  final String? assignedTo;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  const DeliveryQueueEntry({
    required this.orderId,
    this.transactionNumber,
    this.customerId,
    this.customerName,
    this.address,
    this.latitude = 0,
    this.longitude = 0,
    this.distanceKm = 0,
    this.priorityScore = 0,
    this.status = 'Pending Delivery',
    this.type = 'delivery',
    this.assignedTo,
    this.createdAt,
    this.startedAt,
    this.completedAt,
  });

  /// Estimated delivery time based on distance (approx. 6 min per km).
  int get etaMinutes => (distanceKm * 6).round().clamp(10, 60);

  Map<String, dynamic> toMap() {
    return {
      'orderId': orderId,
      'transactionNumber': transactionNumber,
      'customerId': customerId,
      'customerName': customerName,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'distanceKm': distanceKm,
      'priorityScore': priorityScore,
      'status': status,
      'type': type,
      'assignedTo': assignedTo,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'startedAt': startedAt == null ? null : Timestamp.fromDate(startedAt!),
      'completedAt': completedAt == null
          ? null
          : Timestamp.fromDate(completedAt!),
    };
  }

  factory DeliveryQueueEntry.fromMap(Map<String, dynamic> map, String id) {
    // Current queue documents use the order ID as their document ID. Some
    // legacy records stored the order ID only in the document payload, so
    // preserve that canonical task/order ID when it is available.
    final rawOrderId =
        map['orderId'] ?? map['deliveryRequestId'] ?? map['order_id'] ?? id;
    final orderId = rawOrderId.toString().trim().isEmpty
        ? id
        : rawOrderId.toString();

return DeliveryQueueEntry(
      orderId: orderId,
      transactionNumber: map['transactionNumber'],
      customerId: map['customerId'],
      customerName: map['customerName'],
      address: map['address'],
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
      distanceKm: (map['distanceKm'] ?? 0).toDouble(),
      priorityScore: (map['priorityScore'] ?? 0).toInt(),
      status: map['status'] ?? 'Pending Delivery',
      type: map['type'] ?? 'delivery',
      assignedTo: map['assignedTo'],
      createdAt: _parseDate(map['createdAt']),
      startedAt: _parseDate(map['startedAt']),
      completedAt: _parseDate(map['completedAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
