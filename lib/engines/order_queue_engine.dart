import '../models/order_model.dart';
import '../models/delivery_model.dart';
import 'delivery_priority_engine.dart';

class OrderQueueEngine {
  /// Queue orders by priority and FIFO
  static List<OrderModel> processQueue(List<OrderModel> orders) {
    final queue = List<OrderModel>.from(orders);

    // Sort: priority orders first, then by FIFO
    queue.sort((a, b) {
      // Paid orders first
      if (a.paymentStatus == 'Approved' && b.paymentStatus != 'Approved') {
        return -1;
      }
      if (b.paymentStatus == 'Approved' && a.paymentStatus != 'Approved') {
        return 1;
      }

      // Processing orders next
      if (a.status.isProcessing && !b.status.isProcessing) return -1;
      if (b.status.isProcessing && !a.status.isProcessing) return 1;

      // FIFO for same status
      return a.createdAt.compareTo(b.createdAt);
    });

    return queue;
  }

  /// Get next order in queue
  static OrderModel? getNextOrder(List<OrderModel> orders) {
    final queue = processQueue(orders);
    return queue.isNotEmpty ? queue.first : null;
  }

  /// Estimate wait time based on queue position
  static String estimateWaitTime(int position, int averageMinutesPerOrder) {
    final totalMinutes = position * averageMinutesPerOrder;
    if (totalMinutes < 60) {
      return '$totalMinutes mins';
    }
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    return '${hours}h ${mins}m';
  }
}
