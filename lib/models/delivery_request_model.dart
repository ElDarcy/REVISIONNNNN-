import 'package:cloud_firestore/cloud_firestore.dart';

class DeliveryRequestModel {
  final String orderId;
  final String customerId;
  final String? customerName;
  final String status;
  final String source;
  final DateTime? requestedAt;
  final DateTime? deadlineAt;
  final DateTime? assignedAt;
  final DateTime? startedAt;
  final DateTime? deliveredAt;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? assignedTo;
  final double? deliveryFee;
  final String? paymentMethod;
  final String? paymentStatus;
  final String? addressSnapshot;
  final double? latitude;
  final double? longitude;
  final double? distanceKm;

  const DeliveryRequestModel({
    required this.orderId,
    required this.customerId,
    this.customerName,
    this.status = 'requested',
    this.source = 'customer',
    this.requestedAt,
    this.deadlineAt,
    this.assignedAt,
    this.startedAt,
    this.deliveredAt,
    this.completedAt,
    this.createdAt,
    this.updatedAt,
    this.assignedTo,
    this.deliveryFee,
    this.paymentMethod,
    this.paymentStatus,
    this.addressSnapshot,
    this.latitude,
    this.longitude,
    this.distanceKm,
  });

  bool get isActive => const {
        'requested',
        'pickup_deadline_expired',
        'queued',
        'assigned',
        'out_for_delivery',
      }.contains(status);

  bool get isTerminal => const {
        'delivered',
        'completed',
        'expired',
      }.contains(status);

  Map<String, dynamic> toMap() {
    return {
      'orderId': orderId,
      'customerId': customerId,
      'customerName': customerName,
      'status': status,
      'source': source,
      'requestedAt': requestedAt == null ? null : Timestamp.fromDate(requestedAt!),
      'deadlineAt': deadlineAt == null ? null : Timestamp.fromDate(deadlineAt!),
      'assignedAt': assignedAt == null ? null : Timestamp.fromDate(assignedAt!),
      'startedAt': startedAt == null ? null : Timestamp.fromDate(startedAt!),
      'deliveredAt': deliveredAt == null ? null : Timestamp.fromDate(deliveredAt!),
      'completedAt': completedAt == null ? null : Timestamp.fromDate(completedAt!),
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
      'assignedTo': assignedTo,
      'deliveryFee': deliveryFee,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'addressSnapshot': addressSnapshot,
      'latitude': latitude,
      'longitude': longitude,
      'distanceKm': distanceKm,
    };
  }

  factory DeliveryRequestModel.fromMap(Map<String, dynamic> map, String id) {
    return DeliveryRequestModel(
      orderId: id,
      customerId: map['customerId'] ?? '',
      customerName: map['customerName'],
      status: map['status'] ?? 'requested',
      source: map['source'] ?? 'customer',
      requestedAt: _parseDate(map['requestedAt']),
      deadlineAt: _parseDate(map['deadlineAt']),
      assignedAt: _parseDate(map['assignedAt']),
      startedAt: _parseDate(map['startedAt']),
      deliveredAt: _parseDate(map['deliveredAt']),
      completedAt: _parseDate(map['completedAt']),
      createdAt: _parseDate(map['createdAt']),
      updatedAt: _parseDate(map['updatedAt']),
      assignedTo: map['assignedTo'],
      deliveryFee: (map['deliveryFee'] as num?)?.toDouble(),
      paymentMethod: map['paymentMethod'],
      paymentStatus: map['paymentStatus'],
      addressSnapshot: map['addressSnapshot'],
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      distanceKm: (map['distanceKm'] as num?)?.toDouble(),
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
