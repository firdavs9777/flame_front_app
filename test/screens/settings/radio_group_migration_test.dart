// The theme picker and the language picker were migrated off the deprecated
// Radio.groupValue/onChanged pair onto a RadioGroup ancestor. That refactor
// moves the callback off the tile and onto the group: get it wrong and the
// tiles still render, still show a selection, and simply stop responding to
// taps. Nothing in the suite would have said so — the theme picker had only a
// provider test and the language picker had none at all.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/core/i18n/locale_provider.dart';
import 'package:flame/providers/settings_provider.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/screens/settings/language_screen.dart';
import 'package:flame/screens/settings/settings_screen.dart';
import 'package:flame/services/user_service.dart';

User _user() => User.fromJson({
      'id': 'u1', 'name': 'Alex', 'age': 28, 'bio': '',
      'interests': <String>[], 'gender': 'male', 'looking_for': 'female',
      'photos': <String>[],
    });

Widget _host(Widget screen) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWith(
          (ref) => CurrentUserNotifier(UserService())..setUser(_user()),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: screen,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping a theme still changes the theme', (tester) async {
    late WidgetRef ref;
    await tester.pumpWidget(_host(
      Consumer(builder: (context, r, _) {
        ref = r;
        return const SettingsScreen();
      }),
    ));
    await tester.pump();

    expect(ref.read(settingsProvider).themeMode, ThemeMode.system);

    // The Appearance card is below the fold on a test-sized surface.
    await tester.scrollUntilVisible(find.text('Dark'), 200);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    expect(
      ref.read(settingsProvider).themeMode,
      ThemeMode.dark,
      reason: 'the RadioGroup ancestor must carry onChanged now that the '
          'tiles no longer do',
    );
  });

  testWidgets('the theme radios reflect the stored choice', (tester) async {
    await tester.pumpWidget(_host(const SettingsScreen()));
    await tester.pump();

    await tester.scrollUntilVisible(find.text('System'), 200);
    final tile = tester.widget<RadioListTile<ThemeMode>>(
      find.widgetWithText(RadioListTile<ThemeMode>, 'System'),
    );
    // groupValue lives on the ancestor now; the tile only knows its own value.
    expect(tile.value, ThemeMode.system);
  });

  testWidgets('tapping a language still changes the locale', (tester) async {
    late WidgetRef ref;
    await tester.pumpWidget(_host(
      Consumer(builder: (context, r, _) {
        ref = r;
        return const LanguageScreen();
      }),
    ));
    await tester.pumpAndSettle();

    final korean = kSupportedLocales.firstWhere((l) => l.languageCode == 'ko');

    // 32 locales in one ListView — Korean is well below the fold.
    await tester.scrollUntilVisible(find.text(displayNameOf(korean)), 200);
    await tester.ensureVisible(find.text(displayNameOf(korean)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(displayNameOf(korean)));
    await tester.pumpAndSettle();

    expect(
      ref.read(localeProvider),
      korean,
      reason: 'the picker offers 32 locales and had no widget test at all',
    );
  });
}
