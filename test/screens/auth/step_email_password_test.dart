import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/services/auth_availability_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;
import 'package:flame/providers/auth_availability_provider.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/screens/auth/registration/steps/step_email_password.dart';

/// Fake availability service driven by [outcome].
class _FakeAvailabilityService extends AuthAvailabilityService {
  final ServiceResult<bool> outcome;
  int calls = 0;
  _FakeAvailabilityService(this.outcome);

  @override
  Future<ServiceResult<bool>> checkEmail(String email) async {
    calls++;
    return outcome;
  }
}

Widget _host({
  required _FakeAvailabilityService fake,
  required RegistrationData data,
  required VoidCallback onNext,
}) {
  return ProviderScope(
    overrides: [
      authAvailabilityServiceProvider.overrideWithValue(fake),
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
        body: StepEmailPassword(data: data, onNext: onNext),
      ),
    ),
  );
}

Future<void> _fillFormAndSubmit(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'user@example.com');
  await tester.enterText(fields.at(1), 'Password1');
  await tester.enterText(fields.at(2), 'Password1');
  await tester.pump();
  // Accept terms so Continue is enabled.
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Continue'));
  await tester.pump(); // start async check
  await tester.pump(); // resolve future
}

void main() {
  testWidgets('taken email shows inline error and does NOT advance',
      (tester) async {
    final fake = _FakeAvailabilityService(ServiceResult.success(false));
    var nextCalled = false;

    await tester.pumpWidget(_host(
      fake: fake,
      data: RegistrationData(),
      onNext: () => nextCalled = true,
    ));
    await tester.pumpAndSettle();

    await _fillFormAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(fake.calls, 1);
    expect(nextCalled, isFalse);
    expect(find.text('That email is already registered'), findsOneWidget);
    expect(find.text('Log in instead'), findsOneWidget);
  });

  testWidgets('available email advances via onNext', (tester) async {
    final fake = _FakeAvailabilityService(ServiceResult.success(true));
    var nextCalled = false;

    await tester.pumpWidget(_host(
      fake: fake,
      data: RegistrationData(),
      onNext: () => nextCalled = true,
    ));
    await tester.pumpAndSettle();

    await _fillFormAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(fake.calls, 1);
    expect(nextCalled, isTrue);
    expect(find.text('That email is already registered'), findsNothing);
  });

  testWidgets('failed check fails open and still advances', (tester) async {
    final fake = _FakeAvailabilityService(ServiceResult.failure('offline'));
    var nextCalled = false;

    await tester.pumpWidget(_host(
      fake: fake,
      data: RegistrationData(),
      onNext: () => nextCalled = true,
    ));
    await tester.pumpAndSettle();

    await _fillFormAndSubmit(tester);
    await tester.pumpAndSettle();

    expect(fake.calls, 1);
    expect(nextCalled, isTrue);
    expect(find.text('That email is already registered'), findsNothing);
  });
}
