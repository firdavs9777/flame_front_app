import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/screens/auth/registration/steps/step_bio_interests.dart';

Widget _host(RegistrationData data, VoidCallback onNext) {
  // ProviderScope: the step now reads languageCatalogProvider for the two
  // language rows below the interests grid.
  return ProviderScope(
    child: MaterialApp(
      // Interest chips read their labels from the ARBs now, so the step needs
      // localizations to build at all.
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: StepBioInterests(data: data, onNext: onNext),
      ),
    ),
  );
}

void main() {
  test('canContinue requires at least one interest (bio optional)', () {
    expect(canContinue(0), isFalse);
    expect(canContinue(1), isTrue);
    expect(canContinue(3), isTrue);
  });

  testWidgets('neither button is disabled — the requirement is SHOWN instead',
      (tester) async {
    // Reversed deliberately, on 2026-09-02. This test used to assert that
    // Continue was disabled with 0 interests, and Skip was disabled by the
    // same flag. App Review rejected the build under Guideline 2.1(a):
    // "The Skip for now button was unresponsive to taps in account creation."
    //
    // It was disabled, so it was. Both share the same precondition — the
    // backend requires an interest either way — so disabling one and not the
    // other would be incoherent. Both now respond and say what is missing,
    // and the requirement is stated inline before anything is tapped.
    await tester.pumpWidget(_host(RegistrationData(), () {}));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register_interests_hint')), findsOneWidget,
        reason: 'the reason must be visible without tapping to discover it');

    // Pick one interest: the requirement is met, so the hint goes.
    await tester.tap(find.text('Travel'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register_interests_hint')), findsNothing);
  });

  testWidgets('Continue advances with >=1 interest and no bio', (tester) async {
    final data = RegistrationData();
    var nextCalled = false;

    await tester.pumpWidget(_host(data, () => nextCalled = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Music'));
    await tester.pumpAndSettle();

    final continueBtn = find.widgetWithText(ElevatedButton, 'Continue');
    await tester.ensureVisible(continueBtn);
    await tester.pumpAndSettle();
    await tester.tap(continueBtn);
    await tester.pumpAndSettle();

    expect(nextCalled, isTrue);
    expect(data.bio, '');
    expect(data.interests, ['Music']);
  });

  testWidgets('"Skip for now" advances (bio left empty)', (tester) async {
    final data = RegistrationData();
    var nextCalled = false;

    await tester.pumpWidget(_host(data, () => nextCalled = true));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();

    final skipBtn = find.widgetWithText(TextButton, 'Skip for now');
    await tester.ensureVisible(skipBtn);
    await tester.pumpAndSettle();
    await tester.tap(skipBtn);
    await tester.pumpAndSettle();

    expect(nextCalled, isTrue);
    expect(data.bio, '');
    expect(data.interests, ['Food']);
  });
}
