import 'package:url_launcher/url_launcher.dart';

/// Navigation service that opens external map navigation (Google Maps).
///
/// This is intentionally modular so a future Google Maps SDK integration can
/// replace the implementation without changing callers.
class NavigationService {
  /// Opens Google Maps navigation to the given coordinates.
  ///
  /// Tries the native Google Maps app first (`google.navigation:q=lat,lng`),
  /// falling back to the web URL when the app is unavailable.
  static Future<bool> openNavigation({
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    final query = label == null
        ? '$latitude,$longitude'
        : '$latitude,$longitude';
    final uri = Uri.parse('google.navigation:q=$query');

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched) return true;

    // Fallback to Google Maps web search.
    final webUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
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
