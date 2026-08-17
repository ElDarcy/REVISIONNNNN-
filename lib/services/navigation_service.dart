import 'package:url_launcher/url_launcher.dart';

/// Navigation service that opens external map navigation (Google Maps).
///
/// This is intentionally modular so a future Google Maps SDK integration can
/// replace the implementation without changing callers.
class NavigationService {
  static bool hasUsableCoordinates(double? latitude, double? longitude) {
    return latitude != null &&
        longitude != null &&
        latitude.isFinite &&
        longitude.isFinite &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180 &&
        !(latitude == 0 && longitude == 0);
  }

  static Uri? buildNavigationUri({
    double? latitude,
    double? longitude,
    String? address,
    bool webFallback = false,
  }) {
    final hasCoordinates = hasUsableCoordinates(latitude, longitude);
    final destination = hasCoordinates
        ? '${latitude!},${longitude!}'
        : (address?.trim() ?? '');
    if (destination.isEmpty) return null;
    if (hasCoordinates && !webFallback) {
      return Uri.parse('google.navigation:q=$destination');
    }
    return Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destination)}',
    );
  }

  /// Opens Google Maps navigation using coordinates, with an address fallback.
  ///
  /// Tries the native Google Maps app first (`google.navigation:q=lat,lng`),
  /// falling back to the web URL when the app is unavailable.
  static Future<bool> openNavigation({
    double? latitude,
    double? longitude,
    String? address,
    String? label,
  }) async {
    final uri = buildNavigationUri(
      latitude: latitude,
      longitude: longitude,
      address: address,
    );
    if (uri == null) return false;

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) return true;

    // Fallback to Google Maps web search.
    final webUri = buildNavigationUri(
      latitude: latitude,
      longitude: longitude,
      address: address,
      webFallback: true,
    );
    if (webUri == null) return false;
    return launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  /// Opens a Google Maps location / search query for the given coordinate.
  static Future<bool> openMap({
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
