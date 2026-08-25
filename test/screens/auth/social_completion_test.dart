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

  testWidgets('opens on a four-step wizard, with no email/password step',
      (tester) async {
    await tester.pumpWidget(wrap());
    // StepWizard's header/progress/step-info fade in via flutter_animate; a
    // bare pump() leaves their timers pending and trips the "Timer is still
    // pending" invariant check at teardown. step_wizard_test.dart uses the
    // same one-second pump for its initial render — mirrored here.
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(StepWizard), findsOneWidget);
    // A social user already has credentials — asking for a password again
    // would be nonsense, so the flow starts at profile info.
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.text('About You'), findsOneWidget);
  });

  testWidgets('step 1 offers no back affordance — there is nowhere to go',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump(const Duration(seconds: 1));

    // The user is already authenticated; backing out would strand them
    // between signed-in and unusable.
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
  });
}
