import 'delivery_model.dart';

class DeliveryQueueModel {
  final List<DeliveryModel> deliveries;

  DeliveryQueueModel({this.deliveries = const []});

  List<DeliveryModel> get sortedDeliveries {
    final sorted = List<DeliveryModel>.from(deliveries);
    sorted.sort((a, b) {
      final priorityOrder = {'High': 0, 'Medium': 1, 'Low': 2};
      final aPriority = priorityOrder[a.priority] ?? 1;
      final bPriority = priorityOrder[b.priority] ?? 1;
      if (aPriority != bPriority) return aPriority.compareTo(bPriority);
      return a.createdAt.compareTo(b.createdAt);
    });
    return sorted;
  }

  List<DeliveryModel> get pendingDeliveries =>
      deliveries.where((d) => d.status == 'Pending').toList();

  List<DeliveryModel> get inTransitDeliveries =>
      deliveries.where((d) => d.status == 'In Transit').toList();

  List<DeliveryModel> get completedDeliveries =>
      deliveries.where((d) => d.status == 'Delivered').toList();
}
