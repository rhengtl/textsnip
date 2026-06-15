import 'package:flutter_test/flutter_test.dart';
import 'package:textsnip/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TextSnipApp());
    expect(find.text('TextSnip'), findsOneWidget);
  });
}
