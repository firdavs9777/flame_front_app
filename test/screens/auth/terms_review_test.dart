import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/screens/auth/terms_review_screen.dart';

// Two groups hold accounts having agreed to nothing on record: everyone who
// signed up before consent was stored at all, and every social signup, whose
// path had no checkbox. The server reports termsAcceptedAt: null for both.
// This screen is where that gets resolved — once, before the app is usable.

class _StubAuthNotifier extends AuthNotifier {
  int logouts = 0;
  @override
  Future<void> logout() async {
    logouts++;
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget wrap(_StubAuthNotifier auth) => ProviderScope(
        overrides: [authProvider.overrideWith((ref) => auth)],
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: kSupportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: TermsReviewScreen(),
        ),
      );

  testWidgets('names itself for someone already using the app', (tester) async {
    await tester.pumpWidget(wrap(_StubAuthNotifier()));
    await tester.pumpAndSettle();

    // Not "Before you start" — they started a long time ago.
    expect(find.text('Please review our terms'), findsOneWidget);
  });

  testWidgets('both documents are reachable before agreeing', (tester) async {
    await tester.pumpWidget(wrap(_StubAuthNotifier()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Terms of Service'), findsOneWidget);
    expect(find.textContaining('Privacy Policy'), findsOneWidget);
  });

  testWidgets('Continue is inert until the box is ticked', (tester) async {
    await tester.pumpWidget(wrap(_StubAuthNotifier()));
    await tester.pumpAndSettle();

    // No network call is stubbed here, so a live Continue would throw rather
    // than fail quietly — which is exactly what makes this assertion mean
    // something.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Please review our terms'), findsOneWidget,
        reason: 'tapping a disabled Continue must not advance or crash');
  });

  testWidgets('declining signs out rather than dismissing', (tester) async {
    final auth = _StubAuthNotifier();
    await tester.pumpWidget(wrap(auth));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    // The service cannot be used without these terms, so there is no third
    // outcome where they stay signed in having refused.
    expect(auth.logouts, 1);
  });
}
