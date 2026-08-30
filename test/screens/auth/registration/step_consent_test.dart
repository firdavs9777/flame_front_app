import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/screens/auth/registration/steps/step_consent.dart';

// Anyone signing up with Apple or Google used to reach a finished account
// having agreed to nothing: the consent checkbox existed only on the email
// step, and the welcome screen's notice is passive text with no way to open
// either document. These pin the gate that closed that.

var nextTaps = 0;
var declineTaps = 0;

Widget _host(ValueNotifier<bool> accepted) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StepConsent(
          accepted: accepted,
          onNext: () => nextTaps++,
          onDecline: () => declineTaps++,
        ),
      ),
    );

void main() {
  setUp(() {
    nextTaps = 0;
    declineTaps = 0;
  });

  testWidgets('Continue does nothing until the box is ticked', (tester) async {
    final accepted = ValueNotifier<bool>(false);
    addTearDown(accepted.dispose);
    await tester.pumpWidget(_host(accepted));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(nextTaps, 0, reason: 'advancing without consent is the whole bug');
  });

  testWidgets('ticking the box lets the user continue', (tester) async {
    final accepted = ValueNotifier<bool>(false);
    addTearDown(accepted.dispose);
    await tester.pumpWidget(_host(accepted));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(accepted.value, isTrue);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(nextTaps, 1);
  });

  testWidgets('both documents are reachable before agreeing', (tester) async {
    final accepted = ValueNotifier<bool>(false);
    addTearDown(accepted.dispose);
    await tester.pumpWidget(_host(accepted));
    await tester.pumpAndSettle();

    expect(find.textContaining('I agree to the'), findsOneWidget);
    // The link text is what carries the tap recognizers.
    expect(find.textContaining('Terms of Service'), findsOneWidget);
    expect(find.textContaining('Privacy Policy'), findsOneWidget);
  });

  testWidgets('declining is offered explicitly, not just a back arrow',
      (tester) async {
    final accepted = ValueNotifier<bool>(false);
    addTearDown(accepted.dispose);
    await tester.pumpWidget(_host(accepted));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(declineTaps, 1);
    expect(nextTaps, 0);
  });

  testWidgets('an answer survives leaving and returning to the step',
      (tester) async {
    // The flow owns the notifier precisely so swiping back does not silently
    // clear a box the user already ticked.
    final accepted = ValueNotifier<bool>(true);
    addTearDown(accepted.dispose);
    await tester.pumpWidget(_host(accepted));
    await tester.pumpAndSettle();

    final box = tester.widget<Checkbox>(find.byType(Checkbox));
    expect(box.value, isTrue);
  });
}
