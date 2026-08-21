import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/screens/auth/registration/steps/step_bio_interests.dart';

Widget _host(RegistrationData data, VoidCallback onNext) {
  return MaterialApp(
    // Interest chips read their labels from the ARBs now, so the step needs
    // localizations to build at all.
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: StepBioInterests(data: data, onNext: onNext),
    ),
  );
}

void main() {
  test('canContinue requires at least one interest (bio optional)', () {
    expect(canContinue(0), isFalse);
    expect(canContinue(1), isTrue);
    expect(canContinue(3), isTrue);
  });

  testWidgets('Continue is disabled with 0 interests, enabled after picking one',
      (tester) async {
    await tester.pumpWidget(_host(RegistrationData(), () {}));
    await tester.pumpAndSettle();

    ElevatedButton continueButton() =>
        tester.widget<ElevatedButton>(find.byType(ElevatedButton));

    // No interest selected yet.
    expect(continueButton().onPressed, isNull);

    // Pick one interest.
    await tester.tap(find.text('Travel'));
    await tester.pumpAndSettle();

    expect(continueButton().onPressed, isNotNull);
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
