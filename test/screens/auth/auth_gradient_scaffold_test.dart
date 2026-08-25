import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/screens/auth/widgets/auth_gradient_scaffold.dart';

void main() {
  testWidgets('renders its child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGradientScaffold(child: Text('body')),
      ),
    );
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('shows no back button when onBack is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGradientScaffold(child: Text('body')),
      ),
    );
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
  });

  testWidgets('a back button invokes onBack', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGradientScaffold(
          onBack: () => tapped = true,
          child: const Text('body'),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    expect(tapped, isTrue);
  });

  testWidgets('scrollable: false omits the scroll view', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGradientScaffold(scrollable: false, child: Text('body')),
      ),
    );
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('body'), findsOneWidget);
  });
}
