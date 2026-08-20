import 'package:flutter/material.dart';
import '../utils/status_display_helper.dart';

/// Reusable status badge with consistent color scheme.
///
/// Badge colors:
/// - Amber: Pending / Waiting / Requires Action
/// - Blue: Processing / In Progress
/// - Purple: Verification / Review
/// - Green: Verified / Completed / Success
/// - Orange: Ready / Action Required
/// - Red: Rejected / Failed / Cancelled
/// - Grey: Inactive / Disabled / Neutral
class StatusBadge extends StatelessWidget {
  final String status;
  final bool isCustomerFacing;
  final bool small;
  final bool outlined;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.status,
    this.isCustomerFacing = false,
    this.small = false,
    this.outlined = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = StatusDisplayHelper.statusColor(status);
    final label = isCustomerFacing
        ? StatusDisplayHelper.customerStatus(status)
        : status;

    if (outlined) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 10,
          vertical: small ? 2 : 4,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: small ? 10 : 14, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: small ? 10 : 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 10,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: small ? 10 : 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: small ? 10 : 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact payment status badge.
class PaymentStatusBadge extends StatelessWidget {
  final String status;
  final bool small;

  const PaymentStatusBadge({
    super.key,
    required this.status,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = StatusDisplayHelper.paymentStatusColor(status);
    final label = StatusDisplayHelper.paymentStatusDisplay(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 10,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: small ? 10 : 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Weight status badge.
class WeightStatusBadge extends StatelessWidget {
  final String? status;
  final bool small;

  const WeightStatusBadge({
    super.key,
    this.status,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = StatusDisplayHelper.weightStatusColor(status);
    final label = StatusDisplayHelper.weightStatusDisplay(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 10,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: small ? 10 : 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// Fulfillment method badge.
class FulfillmentBadge extends StatelessWidget {
  final String? method;
  final bool small;

  const FulfillmentBadge({
    super.key,
    this.method,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final label = StatusDisplayHelper.fulfillmentLabel(method);
    final color = method == null ? Colors.grey : const Color(0xFF1565C0);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 10,
        vertical: small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: small ? 10 : 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
