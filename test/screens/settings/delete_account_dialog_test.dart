// Google Play requires an in-app path to delete the account and its data.
// Flame's dialog demanded a password and bailed on an empty one
// (`if (password.isEmpty) return;`), so a Google signup — which has no password
// at all, and is the ONLY social provider live in prod — could tap Delete
// forever and nothing would happen. Not a hidden edge case: it was every
// social account's only route to the deletion the policy requires.
//
// These drive the real CurrentUserNotifier over a recording UserService so they
// assert the request goes out, not that a local flag moved.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/screens/settings/settings_screen.dart';
import 'package:flame/services/user_service.dart';

class _RecordingUserService extends UserService {
  int deleteCalls = 0;
  String? lastPassword;
  bool succeeds = true;

  @override
  Future<ServiceResult<void>> deleteAccount({
    String? password,
    String? reason,
  }) async {
    deleteCalls++;
    lastPassword = password;
    return succeeds
        ? ServiceResult.success(null)
        : ServiceResult.failure('nope');
  }
}

User _user({required bool hasPassword}) {
  return User.fromJson({
    'id': 'u1',
    'name': 'Alex',
    'age': 28,
    'gender': 'male',
    'looking_for': 'female',
    'photos': <String>[],
    'has_password': hasPassword,
  });
}

Widget _host(User user, _RecordingUserService service) {
  return ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => CurrentUserNotifier(service)..setUser(user),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: const SettingsScreen(),
    ),
  );
}

const _passwordFieldKey = Key('delete_account_password');
const _confirmKey = Key('delete_account_confirm');

/// The Delete account row sits near the bottom of a lazy list, so a default
/// 800x600 surface never builds it. A tall surface renders the whole screen.
Future<void> _pumpSettings(
  WidgetTester tester,
  User user,
  _RecordingUserService service,
) async {
  await tester.binding.setSurfaceSize(const Size(1000, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_host(user, service));
  await tester.pump();
}

Future<void> _openDialog(WidgetTester tester) async {
  final entry = find.text('Delete account');
  await tester.tap(entry.first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a social account is not asked for a password it never had',
      (tester) async {
    final service = _RecordingUserService();
    await _pumpSettings(tester, _user(hasPassword: false), service);
    await _openDialog(tester);

    expect(find.byKey(_passwordFieldKey), findsNothing);

    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();

    expect(service.deleteCalls, 1,
        reason: 'this is the account deletion Play requires — it must go out');
    expect(service.lastPassword, isNull);
  });

  testWidgets('a password account still confirms with its password',
      (tester) async {
    final service = _RecordingUserService();
    await _pumpSettings(tester, _user(hasPassword: true), service);
    await _openDialog(tester);

    expect(find.byKey(_passwordFieldKey), findsOneWidget);

    await tester.enterText(find.byKey(_passwordFieldKey), 'hunter2');
    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();

    expect(service.deleteCalls, 1);
    expect(service.lastPassword, 'hunter2');
  });

  testWidgets('a password account cannot delete with an empty box',
      (tester) async {
    final service = _RecordingUserService();
    await _pumpSettings(tester, _user(hasPassword: true), service);
    await _openDialog(tester);

    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();

    expect(service.deleteCalls, 0,
        reason: 'the server would reject it anyway; do not fire a doomed call');
  });
}
