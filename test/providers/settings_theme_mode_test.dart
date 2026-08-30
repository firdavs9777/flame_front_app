import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to dark', () {
    // A deliberate look, not a deference to the OS: the palette and the deck
    // were built dark-first, and following the system meant half the users
    // never saw the app the way it was designed.
    final notifier = SettingsNotifier();
    expect(notifier.state.themeMode, ThemeMode.dark);
  });

  test('an explicit System choice survives the change of default', () async {
    // 'never chose' and 'chose System' used to collapse into the same branch.
    // They are different answers, and only one of them may be overridden.
    SharedPreferences.setMockInitialValues({'theme_mode': 'system'});

    final notifier = SettingsNotifier();
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.themeMode, ThemeMode.system);
  });

  test('an unrecognised stored value falls back to the default', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'chartreuse'});

    final notifier = SettingsNotifier();
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.themeMode, ThemeMode.dark);
  });

  test('setThemeMode updates state and persists the choice', () async {
    final notifier = SettingsNotifier();

    await notifier.setThemeMode(ThemeMode.light);
    expect(notifier.state.themeMode, ThemeMode.light);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'light');
  });

  test('choosing the mode already on screen is still recorded', () async {
    // Dark is the default, so tapping Dark is a no-op on state — but it is the
    // moment "we chose this for them" becomes "they chose it", and a later
    // change of default must not overrule it.
    final notifier = SettingsNotifier();
    expect(notifier.state.themeMode, ThemeMode.dark);

    await notifier.setThemeMode(ThemeMode.dark);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');
  });

  test('a persisted choice is loaded on construction', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'light'});

    final notifier = SettingsNotifier();
    // _loadThemeMode runs asynchronously in the constructor.
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.themeMode, ThemeMode.light);
  });

  // There is no longer a "leaves other settings untouched" case to make:
  // AppSettings holds themeMode and nothing else. The three booleans this
  // assertion used to guard (showOnlineStatus, discoveryEnabled, showDistance)
  // were in-memory only — no request, no SharedPreferences write. Two of them
  // were read solely by the switch that set them, and the third had a
  // server-backed twin in Edit Profile that it silently contradicted. All
  // three are gone; showOnlineStatus now lives on User.preferences, where the
  // server can see it. See test/screens/settings/settings_online_status_test.
}
