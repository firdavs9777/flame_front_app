import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/core/languages/language_fallback.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/providers/languages_provider.dart';
import 'package:flame/screens/auth/registration/registration_draft.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/screens/auth/registration/steps/step_bio_interests.dart';

/// A notifier whose state the test drives directly — avoids exercising the
/// real AuthNotifier's network/session-restore side effects.
class _StubAuthNotifier extends AuthNotifier {
  void emit(AuthState next) => state = next;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resuming a draft', () {
    testWidgets(
        'restores step 0\'s email field, not just the resumed step',
        (tester) async {
      const savedEmail = 'saved-draft@example.com';
      SharedPreferences.setMockInitialValues({
        'registration_draft': jsonEncode({
          'email': savedEmail,
          'name': 'Dana',
          'age': 25,
          'gender': 'female',
          'lookingFor': 'male',
          'bio': '',
          'interests': <String>[],
          'latitude': null,
          'longitude': null,
          'photoFilePaths': <String>[],
          // A step past 0 — the clamp in resumeStepFor always lands back on
          // step 0 anyway (no password is ever persisted), which is exactly
          // what exposed the stale-controller bug this test guards against.
          'step': 2,
        }),
      });

      final notifier = _StubAuthNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => notifier),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: kSupportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const RegistrationFlow(),
          ),
        ),
      );

      // Let the post-frame callback's `_draft.load()` future resolve and the
      // resume dialog build.
      await tester.pump();
      await tester.pump();

      expect(find.text('Resume your signup?'), findsOneWidget);

      await tester.tap(find.text('Resume'));
      await tester.pump();
      // flutter_animate leaves a pending timer alive on freshly-built steps.
      await tester.pump(const Duration(seconds: 1));

      expect(find.text(savedEmail), findsOneWidget);
    });
  });

  group('the draft round-trips the language lists', () {
    test('toJson/fromJson preserves both lists', () {
      const draft = RegistrationDraft();
      final data = RegistrationData()
        ..email = 'a@b.com'
        ..languagesSpoken = ['ko', 'en']
        ..languagesLearning = ['fr'];

      final restored = draft.fromJson(draft.toJson(data, 3));

      expect(restored.languagesSpoken, ['ko', 'en']);
      expect(restored.languagesLearning, ['fr']);
    });

    test('a draft written before this release has no language keys — reads '
        'as [], not null', () {
      const draft = RegistrationDraft();
      final restored = draft.fromJson({
        'email': 'old@draft.com',
        // no 'languagesSpoken' / 'languagesLearning' keys at all.
      });

      expect(restored.languagesSpoken, isEmpty);
      expect(restored.languagesLearning, isEmpty);
    });

    testWidgets(
        'a restored, non-empty languagesSpoken survives _seedFromLocale — '
        'the device locale must not clobber a real choice', (tester) async {
      // Simulates the post-restore state: languagesSpoken is already
      // populated, as _restoreFrom now leaves it. The device locale below
      // ('en') differs from the restored choice ('ko'), so if the seeding
      // guard failed to see the restored value, the row would show English
      // instead of the Korean the user actually picked.
      final data = RegistrationData()..languagesSpoken = ['ko'];

      await tester.pumpWidget(ProviderScope(
        overrides: [
          languageCatalogProvider.overrideWith((ref) async => kLanguageFallback),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: kSupportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: StepBioInterests(data: data, onNext: () {}),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final spokenRow = find.byKey(const Key('register_languages_spoken'));
      expect(
        find.descendant(of: spokenRow, matching: find.text('한국어')),
        findsOneWidget,
        reason: 'the restored choice must still be shown',
      );
      expect(
        find.descendant(of: spokenRow, matching: find.text('English')),
        findsNothing,
        reason: 'the device locale must not have overwritten it',
      );
      expect(data.languagesSpoken, ['ko']);
    });
  });

  group('locale seeding happens once per DRAFT, not once per State', () {
    // StepWizard's PageView keeps no state, so step 4's State is destroyed the
    // moment the user advances to step 5. A latch living on that State was
    // therefore reset on the way back, and a user who had deliberately emptied
    // "Languages you speak" got the device locale silently re-added and then
    // persisted. The latch has to outlive the widget, so it lives on the draft
    // beside the languages themselves.
    Widget host(RegistrationData data, {required Locale locale, Key? key}) {
      return ProviderScope(
        overrides: [
          languageCatalogProvider.overrideWith((ref) async => kLanguageFallback),
        ],
        child: MaterialApp(
          locale: locale,
          supportedLocales: kSupportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: StepBioInterests(key: key, data: data, onNext: () {}),
          ),
        ),
      );
    }

    testWidgets('a genuinely fresh draft still seeds from the device locale',
        (tester) async {
      final data = RegistrationData();

      await tester.pumpWidget(host(data, locale: const Locale('ko')));
      await tester.pumpAndSettle();

      expect(data.languagesSpoken, ['ko']);
      expect(data.languagesSeeded, isTrue);
    });

    testWidgets('a cleared list stays cleared when the step is rebuilt',
        (tester) async {
      final data = RegistrationData();

      await tester.pumpWidget(
        host(data, locale: const Locale('ko'), key: const ValueKey(1)),
      );
      await tester.pumpAndSettle();
      expect(data.languagesSpoken, ['ko'], reason: 'seeded on the first build');

      // The user empties the row and walks on to step 5.
      data.languagesSpoken = [];

      // Coming back builds a brand new State — a different key is exactly what
      // the PageView does to this widget.
      await tester.pumpWidget(
        host(data, locale: const Locale('ko'), key: const ValueKey(2)),
      );
      await tester.pumpAndSettle();

      expect(data.languagesSpoken, isEmpty,
          reason: 'deliberately saying "I speak nothing" must survive');
    });

    test('the seeded flag survives a draft round trip', () {
      const draft = RegistrationDraft();
      final data = RegistrationData()
        ..languagesSeeded = true
        ..languagesSpoken = [];

      final restored = draft.fromJson(draft.toJson(data, 4));

      expect(restored.languagesSeeded, isTrue);
      expect(restored.languagesSpoken, isEmpty);
    });

    test('a draft written before this release has not been seeded', () {
      const draft = RegistrationDraft();
      final restored = draft.fromJson({'email': 'old@draft.com'});

      expect(restored.languagesSeeded, isFalse,
          reason: 'an older draft never got the chance, so it still should');
    });
  });

  group('resumeStepFor', () {
    test('a draft with no password restores to step 0, whatever it saved', () {
      // The password is deliberately never persisted. Landing the user past
      // step 0 means register() posts '' and the server 422s on min(8) with
      // nothing on screen to explain it.
      expect(
        resumeStepFor(password: '', savedStep: 3, totalSteps: 5),
        0,
      );
    });

    test('a draft with a password honours its saved step', () {
      expect(
        resumeStepFor(password: 'hunter22', savedStep: 3, totalSteps: 5),
        3,
      );
    });

    test('clamps a saved step past the end of the flow', () {
      expect(
        resumeStepFor(password: 'hunter22', savedStep: 99, totalSteps: 5),
        4,
      );
    });

    test('clamps a negative saved step', () {
      expect(
        resumeStepFor(password: 'hunter22', savedStep: -2, totalSteps: 5),
        0,
      );
    });
  });
}
