import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// Centralized status display logic with role-aware labels.
///
/// Customers see friendly, non-technical labels.
/// Staff/admin see operational labels.
class StatusDisplayHelper {
  StatusDisplayHelper._();

  /// Customer-facing status label.
  static String customerStatus(String rawStatus) {
    switch (rawStatus) {
      case 'Pending':
      case 'Pending Payment':
        return 'Awaiting Payment';
      case 'Payment Pending Verification':
        return 'Payment Under Review';
      case 'Payment Verified':
        return 'Transaction Confirmed';
      case 'Order Received':
        return 'Transaction Received';
      case 'Waiting for Machine':
      case 'Machine Assigned':
      case 'Waiting for Dryer':
      case 'Dryer Assigned':
        return 'Preparing Your Laundry';
      case 'Washing':
        return 'Washing';
      case 'Drying':
        return 'Drying';
      case 'Folding':
        return 'Folding';
      case 'Ready for Pickup':
        return 'Ready for Pickup';
      case 'Ready for Delivery':
        return 'Ready for Delivery';
      case 'Out for Delivery':
        return 'Out for Delivery';
      case 'Delivered':
        return 'Delivered';
      case 'Picked Up':
        return 'Picked Up';
      case 'Completed':
        return 'Completed';
      case 'Cancelled':
        return 'Cancelled';
      default:
        return rawStatus;
    }
  }

  /// Staff/admin-facing status label (operational).
  static String staffStatus(String rawStatus) {
    return rawStatus;
  }

  /// Delivery status label for customers.
  static String deliveryStatus(String? status) {
    if (status == null) return 'Not requested';
    switch (status) {
      case 'Pending Delivery':
        return 'Queued for Delivery';
      case 'Out for Delivery':
        return 'On the Way';
      case 'Completed':
        return 'Delivered';
      case 'Cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  /// Fulfillment method label.
  static String fulfillmentLabel(String? method) {
    switch (method) {
      case 'Personal Pickup':
        return 'Personal Pickup';
      case 'Delivery':
        return 'Delivery';
      default:
        return 'Not yet chosen';
    }
  }

  /// Payment status label for customers.
  static String paymentStatusDisplay(String status) {
    switch (status) {
      case 'Verified':
        return 'Paid';
      case 'Pending Verification':
        return 'Under Review';
      case 'Pending Collection':
        return 'Pending Collection';
      case 'Pending':
        return 'Awaiting Payment';
      case 'Rejected':
        return 'Payment Rejected';
      default:
        return status;
    }
  }

  /// Badge color for a given status string.
  static Color statusColor(String status) {
    switch (status) {
      case 'Pending':
      case 'Pending Payment':
      case 'Payment Pending Verification':
        return AppColors.warning;
      case 'Pending Verification':
        return AppColors.warning;
      case 'Pending Collection':
        return AppColors.warning;
      case 'Payment Verified':
      case 'Order Received':
        return AppColors.processingColor;
      case 'Waiting for Machine':
      case 'Waiting for Dryer':
      case 'Machine Assigned':
      case 'Dryer Assigned':
        return Colors.orange;
      case 'Washing':
      case 'Drying':
        return AppColors.accent;
      case 'Ready for Delivery':
      case 'Ready for Pickup':
        return AppColors.success;
      case 'Out for Delivery':
        return const Color(0xFF43A047);
      case 'Delivered':
      case 'Completed':
        return AppColors.success;
      case 'Cancelled':
      case 'Rejected':
        return AppColors.error;
      default:
        return Colors.grey;
    }
  }

  /// Badge color for payment status.
  static Color paymentStatusColor(String status) {
    switch (status) {
      case 'Verified':
        return AppColors.success;
      case 'Pending Verification':
        return AppColors.warning;
      case 'Pending Collection':
        return AppColors.pendingColor;
      case 'Pending':
        return AppColors.pendingColor;
      case 'Rejected':
        return AppColors.error;
      default:
        return Colors.grey;
    }
  }

  /// Badge color for weight status.
  static Color weightStatusColor(String? status) {
    switch (status) {
      case 'verified':
        return AppColors.success;
      case 'submitted':
        return AppColors.warning;
      case 'rejected':
        return AppColors.error;
      case 'pending':
      default:
        return Colors.grey;
    }
  }

  /// Human-readable weight status.
  static String weightStatusDisplay(String? status) {
    switch (status) {
      case 'verified':
        return 'Verified';
      case 'submitted':
        return 'Awaiting Review';
      case 'rejected':
        return 'Rejected - Resubmit';
      case 'pending':
      default:
        return 'Pending Verification';
    }
  }
}
