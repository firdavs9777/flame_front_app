import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/screens/auth/registration/social_profile_completion_flow.dart';
import 'package:flame/screens/auth/registration/step_wizard.dart';

/// A notifier whose state the test drives directly, avoiding the real
/// AuthNotifier's constructor — which calls ApiClient().init() and
/// SharedPreferences.getInstance() and throws MissingPluginException in a
/// widget test.
class _StubAuthNotifier extends AuthNotifier {
  void emit(AuthState next) => state = next;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget wrap() {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _StubAuthNotifier()),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: kSupportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SocialProfileCompletionFlow(),
      ),
    );
  }

  testWidgets('opens on the Terms gate, with no email/password step',
      (tester) async {
    await tester.pumpWidget(wrap());
    // StepWizard's header/progress/step-info fade in via flutter_animate; a
    // bare pump() leaves their timers pending and trips the "Timer is still
    // pending" invariant check at teardown. step_wizard_test.dart uses the
    // same one-second pump for its initial render — mirrored here.
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(StepWizard), findsOneWidget);
    // Was four steps opening on About You. A social user already has
    // credentials, so there is still no password step — but they had also
    // never been shown the Terms or the Privacy Policy, because the consent
    // checkbox lived only on the email step. The gate goes first: agreeing to
    // documents you were never offered is not agreement.
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.text('Before you start'), findsOneWidget);
    expect(find.textContaining('I agree to the'), findsOneWidget);
  });

  testWidgets('the Terms gate can be declined', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump(const Duration(seconds: 1));

    // Everywhere else in this wizard backing out would strand an authenticated
    // user with an unusable profile, which is why there was no back arrow at
    // all. That reasoning does not survive a consent gate: someone who will
    // not accept the terms has to be able to leave, so declining signs out.
    expect(find.text('Not now'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
  });

  testWidgets('profile questions stay behind the gate', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('About You'), findsNothing);
  });
}
