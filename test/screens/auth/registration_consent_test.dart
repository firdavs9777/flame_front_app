import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/screens/auth/registration/steps/step_email_password.dart';
import 'package:flame/screens/auth/registration/legal_document_sheet.dart';

Widget _l10nApp(Widget home) {
  return ProviderScope(
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
}

void main() {
  testWidgets('Continue is disabled until Terms & Privacy are accepted',
      (tester) async {
    await tester.pumpWidget(
      _l10nApp(Scaffold(
        body: StepEmailPassword(data: RegistrationData(), onNext: () {}),
      )),
    );
    await tester.pumpAndSettle();

    ElevatedButton continueButton() =>
        tester.widget<ElevatedButton>(find.byType(ElevatedButton));

    // Gated: no consent yet.
    expect(continueButton().onPressed, isNull);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.textContaining('I agree to the'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // Consent given → enabled.
    expect(continueButton().onPressed, isNotNull);
  });

  testWidgets('tapping opens the Terms document sheet', (tester) async {
    await tester.pumpWidget(
      _l10nApp(Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showLegalDocumentSheet(ctx, LegalDoc.terms),
              child: const Text('open'),
            ),
          ),
        ),
      )),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The placeholder copy ("1. Acceptance of Terms") is gone — these are the
    // real documents now. Pin the first heading so an empty or unstyled sheet
    // still fails, and keep it in step with docs/legal/terms.html.
    expect(find.text('1. Who can use Flame'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('privacy sheet shows the privacy document', (tester) async {
    await tester.pumpWidget(
      _l10nApp(Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showLegalDocumentSheet(ctx, LegalDoc.privacy),
              child: const Text('open'),
            ),
          ),
        ),
      )),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('1. What we collect'), findsOneWidget);
  });
}
