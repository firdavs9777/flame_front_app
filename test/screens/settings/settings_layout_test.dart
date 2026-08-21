import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/screens/settings/settings_screen.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/theme/app_theme.dart';

class _QuietUserService extends UserService {
  @override
  Future<ServiceResult<User>> getCurrentUser() async =>
      ServiceResult.failure('not used');
}

User _user() => User.fromJson({
      'id': 'u1', 'name': 'Alex', 'age': 28, 'bio': '',
      'interests': <String>[], 'gender': 'male', 'looking_for': 'female',
      'photos': <String>[],
    });

Future<void> pumpSettings(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  required ThemeData theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUserProvider.overrideWith(
        (ref) => CurrentUserNotifier(_QuietUserService())..setUser(_user()),
      ),
    ],
    child: MaterialApp(
      theme: theme,
      locale: const Locale('en'),
      supportedLocales: kSupportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const SettingsScreen(),
    ),
  ));
  await tester.pump();
}

void main() {
  const compact = Size(390, 844);
  const expanded = Size(1024, 1366);

  for (final size in [compact, expanded]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'Settings renders clean at ${size.width.toInt()}px, ${scale}x text',
          (tester) async {
        await pumpSettings(tester,
            size: size, textScale: scale, theme: AppTheme.lightTheme);

        // A fixed-height box around text plus a large system font is the failure
        // this catches — the same one the chat popup menu produced.
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Settings renders clean in dark theme', (tester) async {
    await pumpSettings(tester,
        size: compact, textScale: 1.0, theme: AppTheme.darkTheme);

    expect(tester.takeException(), isNull);
  });
}
