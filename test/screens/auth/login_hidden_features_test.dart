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
  testWidgets('social login and forgot-password are hidden in MVP', (tester) async {
    await tester.pumpWidget(_host(const LoginScreen()));
    await tester.pumpAndSettle();

    // Core login still present.
    expect(find.byType(TextFormField), findsWidgets);

    // Hidden features absent (exact l10n English strings).
    expect(find.text('Or continue with'), findsNothing);
    expect(find.text('Forgot password?'), findsNothing);
  });
}
