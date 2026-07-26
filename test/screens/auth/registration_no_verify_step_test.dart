import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';

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
  testWidgets('registration has 5 steps and no verify-email step', (tester) async {
    await tester.pumpWidget(_host(const RegistrationFlow()));
    await tester.pumpAndSettle();

    // Header shows total step count.
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.text('Step 1 of 6'), findsNothing);

    // The verify-email subtitle is never shown as a step.
    expect(find.text('Enter the code we sent you'), findsNothing);
  });
}
