import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: FlameApp()),
    );

    // The splash screen shows the Flame brand on first frame.
    expect(find.text('Flame'), findsOneWidget);

    // Drain the splash's delayed navigation timer and the welcome screen's
    // entry animations so no Timer is left pending when the tree is disposed.
    await tester.pumpAndSettle(const Duration(seconds: 4));
  });
}
