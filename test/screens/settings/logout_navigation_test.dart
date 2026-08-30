// Log out and Delete account both looked dead.
//
// Flipping auth state rebuilds MaterialApp's `home`, but Settings is PUSHED on
// top of it — changing the bottom route leaves the pushed one exactly where it
// is. So the user tapped Log out, the session really did end underneath, and
// they were still looking at Settings. Delete account had it worse: the account
// was gone and every screen still on the stack was showing data that no longer
// existed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/screens/settings/settings_screen.dart';
import 'package:flame/services/auth_service.dart';
import 'package:flame/services/user_service.dart';

class _SilentAuthService extends AuthService {
  int logouts = 0;
  @override
  Future<void> logout() async => logouts++;
}

class _DeletingUserService extends UserService {
  @override
  Future<ServiceResult<void>> deleteMe({String? password}) async =>
      ServiceResult.success(null);
}

User _user() => User.fromJson({
      'id': 'u1', 'name': 'Alex', 'age': 28, 'bio': '',
      'interests': const <String>[], 'gender': 'male', 'looking_for': 'female',
      'photos': const <String>[], 'has_password': true,
    });

late _SilentAuthService auth;

/// A root route with Settings pushed on top — the real shape of the bug.
Widget _host() {
  auth = _SilentAuthService();
  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => AuthNotifier(authService: auth)),
      currentUserProvider.overrideWith(
        (ref) => CurrentUserNotifier(_DeletingUserService())..setUser(_user()),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              child: const Text('open settings'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.pumpWidget(_host());
  await tester.pumpAndSettle();
  await tester.tap(find.text('open settings'));
  await tester.pumpAndSettle();
  expect(find.byType(SettingsScreen), findsOneWidget);
}

/// Settings is a lazy ListView and the danger zone is well below the fold.
/// `scrollable` is explicit because the page nests other scrollables.
Future<void> _tapLogOutRow(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Log out'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Log out'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Log out leaves Settings instead of sitting on it',
      (tester) async {
    await _openSettings(tester);

    await _tapLogOutRow(tester);

    // Confirm in the dialog.
    await tester.tap(find.widgetWithText(TextButton, 'Log out').last);
    await tester.pumpAndSettle();

    expect(auth.logouts, 1, reason: 'the session really does end');
    expect(
      find.byType(SettingsScreen),
      findsNothing,
      reason: 'and the user is taken off the screen they signed out from',
    );
    expect(find.text('open settings'), findsOneWidget);
  });

  testWidgets('Cancel keeps the user where they are', (tester) async {
    await _openSettings(tester);

    await _tapLogOutRow(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await tester.pumpAndSettle();

    expect(auth.logouts, 0);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });
}
