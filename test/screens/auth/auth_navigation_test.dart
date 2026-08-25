import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/screens/auth/login_screen.dart';

/// A notifier whose state the test drives directly.
class _StubAuthNotifier extends AuthNotifier {
  void emit(AuthState next) => state = next;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('login pops itself when the user lands on profileIncomplete',
      (tester) async {
    // Owned by the ProviderScope below; it is disposed automatically when the
    // widget tree tears down at the end of the test. Disposing it a second
    // time here would throw ("used after dispose").
    final notifier = _StubAuthNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => notifier),
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
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                child: const Text('open login'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open login'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    // A social login that needs profile completion. main.dart swaps `home:`
    // underneath; the pushed login screen has to get out of the way or it sits
    // on top of the completion flow forever.
    notifier.emit(const AuthState(status: AuthStatus.profileIncomplete));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsNothing);
  });
}
