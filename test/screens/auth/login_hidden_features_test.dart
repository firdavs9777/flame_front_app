import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/screens/auth/login_screen.dart';

Widget _host(Widget home) => ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: kSupportedLocales,
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
  testWidgets('login shows Google but hides Apple/Facebook and forgot-password',
      (tester) async {
    await tester.pumpWidget(_host(const LoginScreen()));
    await tester.pumpAndSettle();

    // Core login still present.
    expect(find.byType(TextFormField), findsWidgets);

    // Google is live — backend endpoint and iOS keys are configured.
    expect(find.text('Or continue with'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);

    // Still hidden: no native config yet (see docs/social-auth-setup.md).
    expect(find.text('Continue with Apple'), findsNothing);
    expect(find.text('Continue with Facebook'), findsNothing);
    expect(find.text('Forgot password?'), findsNothing);
  });
}
