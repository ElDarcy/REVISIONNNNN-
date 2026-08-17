import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_app/services/navigation_service.dart';

void main() {
  test('navigation prefers the customer coordinates over an address fallback', () {
    final uri = NavigationService.buildNavigationUri(
      latitude: 14.8432,
      longitude: 120.8111,
      address: 'Laundry shop address',
    );

    expect(uri, isNotNull);
    expect(uri.toString(), 'google.navigation:q=14.8432,120.8111');
  });
}
