import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/screens/auth/forgot_password_screen.dart';
import 'package:flame/widgets/kit/kit.dart';

/// Real [AuthNotifier] minus the network call — `forgotPassword` would
/// otherwise hit the live [AuthService], which has nothing to talk to in a
/// widget test.
class _StubAuthNotifier extends AuthNotifier {
  @override
  Future<bool> forgotPassword(String email) async => true;
}

Widget _host(AuthNotifier notifier) => ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => notifier),
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
        home: ForgotPasswordScreen(),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('uses the design-system input and button, not raw Material',
      (tester) async {
    await tester.pumpWidget(_host(_StubAuthNotifier()));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(AppInput), findsOneWidget);
    expect(find.byType(AppButton), findsOneWidget);
  });

  testWidgets('an invalid address is rejected without a request',
      (tester) async {
    await tester.pumpWidget(_host(_StubAuthNotifier()));
    await tester.pump(const Duration(seconds: 1));

    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.tap(find.byType(AppButton));
    await tester.pump();

    expect(find.text('Please enter a valid email'), findsOneWidget);
  });

  testWidgets('plus addressing is accepted — the old regex rejected it',
      (tester) async {
    await tester.pumpWidget(_host(_StubAuthNotifier()));
    await tester.pump(const Duration(seconds: 1));

    await tester.enterText(find.byType(TextFormField), 'ada+reset@gmail.com');
    await tester.tap(find.byType(AppButton));
    await tester.pump();

    expect(find.text('Please enter a valid email'), findsNothing);
  });
}
