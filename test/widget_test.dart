import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: FlameApp()),
    );

    // Verify the app loads with the Flame title
    expect(find.text('Flame'), findsOneWidget);
  });
}
