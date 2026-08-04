import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_app/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LaundryApp());
    expect(find.text('Welcome Back!'), findsOneWidget);
  });
}
