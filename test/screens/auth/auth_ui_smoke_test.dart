import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/widgets/auth/social_sign_in_buttons.dart';
import 'package:flame/screens/auth/welcome_screen.dart';
import 'package:flame/screens/auth/login_screen.dart';

Widget _host(Widget home) => ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: kSupportedLocales,
        theme: AppTheme.lightTheme,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );

void main() {
  testWidgets('welcome renders create-account and sign-in actions',
      (tester) async {
    await tester.pumpWidget(_host(const WelcomeScreen()));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('SocialSignInButtons renders 3 providers when enabled',
      (tester) async {
    await tester.pumpWidget(_host(
      const Scaffold(
        body: SocialSignInButtons(enabledOverride: true),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Facebook'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
  });

  testWidgets('SocialSignInButtons renders nothing when disabled',
      (tester) async {
    await tester.pumpWidget(_host(
      const Scaffold(
        body: SocialSignInButtons(enabledOverride: false),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Continue with Google'), findsNothing);
    expect(find.text('Or continue with'), findsNothing);
  });

  testWidgets('login renders email + password AppInputs and a submit button',
      (tester) async {
    await tester.pumpWidget(_host(const LoginScreen()));
    await tester.pump(const Duration(seconds: 1));

    // Two AppInputs (email + password).
    expect(find.byType(AppInput), findsNWidgets(2));
    // Submit button present.
    expect(find.byType(AppButton), findsOneWidget);
  });
}
