import 'package:flutter/material.dart';
import '../constants/app_sizes.dart';
import '../theme/brand.dart';

/// Confirmation card for a resolved location.
///
/// Displays the formatted address + coordinates + distance from the shop and
/// requires an explicit customer confirmation before the location is saved.
/// "Verify on Map" opens an external map for visual confirmation only — it
/// does NOT perform any geocoding or validation.
class LocationPinCard extends StatelessWidget {
  final String formattedAddress;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final bool inServiceArea;
  final VoidCallback onVerifyOnMap;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final bool isConfirming;

  const LocationPinCard({
    super.key,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.inServiceArea,
    required this.onVerifyOnMap,
    required this.onConfirm,
    this.confirmLabel = 'Confirm & Save',
    this.isConfirming = false,
  });

  @override
  Widget build(BuildContext context) {
    final areaColor = inServiceArea ? BrandColors.success : BrandColors.error;

    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceLg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: BrandColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSizes.spaceSm + 2),
                decoration: BoxDecoration(
                  color: BrandColors.aquaSoft,
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
                child: const Icon(
                  Icons.location_on,
                  color: BrandColors.navy,
                  size: AppSizes.iconMd,
                ),
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: Text(
                  'Your delivery location',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceMd),
          Text(
            formattedAddress,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: BrandColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text(
            '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: BrandColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSizes.spaceMd),
          Row(
            children: [
              Icon(
                inServiceArea
                    ? Icons.check_circle
                    : Icons.error_outline,
                color: areaColor,
                size: AppSizes.iconMd,
              ),
              const SizedBox(width: AppSizes.spaceXs + 2),
              Expanded(
                child: Text(
                  inServiceArea
                      ? 'Inside delivery area · ${distanceKm.toStringAsFixed(1)} km from shop'
                      : 'Outside delivery area · ${distanceKm.toStringAsFixed(1)} km from shop',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: areaColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceMd),
          OutlinedButton.icon(
            onPressed: onVerifyOnMap,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Verify on Map'),
          ),
          const SizedBox(height: AppSizes.spaceSm),
          FilledButton.icon(
            onPressed: inServiceArea && !isConfirming ? onConfirm : null,
            icon: isConfirming
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
            label: Text(isConfirming ? 'Saving…' : confirmLabel),
          ),
        ],
      ),
    );
  }
}