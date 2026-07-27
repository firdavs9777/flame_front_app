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

  test('setThemeMode leaves other settings untouched', () async {
    final notifier = SettingsNotifier();
    final before = notifier.state;

    await notifier.setThemeMode(ThemeMode.dark);

    expect(notifier.state.showOnlineStatus, before.showOnlineStatus);
    expect(notifier.state.discoveryEnabled, before.discoveryEnabled);
    expect(notifier.state.showDistance, before.showDistance);
  });
}
