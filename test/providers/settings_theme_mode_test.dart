import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to ThemeMode.system', () {
    final notifier = SettingsNotifier();
    expect(notifier.state.themeMode, ThemeMode.system);
  });

  test('setThemeMode updates state and persists the choice', () async {
    final notifier = SettingsNotifier();

    await notifier.setThemeMode(ThemeMode.dark);
    expect(notifier.state.themeMode, ThemeMode.dark);

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
