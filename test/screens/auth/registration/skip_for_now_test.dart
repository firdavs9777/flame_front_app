import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/screens/auth/registration/steps/step_bio_interests.dart';

/// App Review, 2026-09-02, Guideline 2.1(a):
///
///   "The Skip for now button was unresponsive to taps in account creation."
///
/// It was. `onPressed` was null until an interest had been selected, so the
/// button was disabled and swallowed every tap without explanation. These pin
/// that no control on this step can ever be dead to a tap again.
Widget _host(RegistrationData data, {VoidCallback? onNext}) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StepBioInterests(
            data: data,
            onNext: onNext ?? () {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('Skip for now RESPONDS with no interests selected', (tester) async {
    final data = RegistrationData();
    await tester.pumpWidget(_host(data));
    await tester.pumpAndSettle();

    final skip = tester.widget<AppButton>(find.byKey(const Key('register_bio_skip')));
    expect(skip.onPressed, isNotNull,
        reason: 'a disabled Skip button is what App Review called unresponsive');
  });

  testWidgets('Continue also responds rather than sitting dead', (tester) async {
    await tester.pumpWidget(_host(RegistrationData()));
    await tester.pumpAndSettle();

    final go = tester.widget<AppButton>(
        find.byKey(const Key('register_bio_continue')));
    expect(go.onPressed, isNotNull);
  });

  testWidgets('the requirement is stated before the user taps anything',
      (tester) async {
    // Responding on tap is necessary but not sufficient: the reason should be
    // visible without having to discover it by tapping.
    await tester.pumpWidget(_host(RegistrationData()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register_interests_hint')), findsOneWidget);
    expect(find.text('Pick at least one interest'), findsOneWidget);
  });

  testWidgets('tapping Skip with nothing selected explains, and does not advance',
      (tester) async {
    var advanced = false;
    await tester.pumpWidget(_host(RegistrationData(), onNext: () => advanced = true));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('register_bio_skip')));
    await tester.pump();

    expect(advanced, isFalse, reason: 'the backend requires an interest');
    // The feedback that makes it responsive rather than broken.
    expect(find.text('Pick at least one interest'), findsWidgets);
  });

  testWidgets('the hint disappears once the requirement is met', (tester) async {
    final data = RegistrationData();
    await tester.pumpWidget(_host(data));
    await tester.pumpAndSettle();

    // The interest chips are GestureDetectors inside a Wrap, not FilterChips.
    final chip = find.descendant(
      of: find.byType(Wrap),
      matching: find.byType(GestureDetector),
    ).first;

    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register_interests_hint')), findsNothing,
        reason: 'the hint has served its purpose once an interest is picked');
  });
}
