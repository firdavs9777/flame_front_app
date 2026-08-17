import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _loadThemeMode();
  }

  static const _kThemeModeKey = 'theme_mode';

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = _themeModeFromString(prefs.getString(_kThemeModeKey));
    if (mode != state.themeMode) {
      state = state.copyWith(themeMode: mode);
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == state.themeMode) return;
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  }
}

ThemeMode _themeModeFromString(String? value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    case 'system':
    default:
      return ThemeMode.system;
  }
}

/// Device-local app settings.
///
/// Only [themeMode] lives here, and deliberately: it is the one setting with
/// no server representation and no server consequence.
///
/// This class used to also carry `showOnlineStatus`, `showDistance` and
/// `discoveryEnabled`. All three were in-memory only — `setThemeMode` is the
/// sole persisting method — so they survived neither a restart nor a request:
///
///  * `showOnlineStatus` had a real server-backed twin in Edit Profile →
///    Preferences. Two controls, one setting, disagreeing. Both now go through
///    `CurrentUserNotifier.updatePreferences`.
///  * `showDistance` and `discoveryEnabled` were read only by the switch that
///    set them — dead controls. `showDistance` must not return as a
///    server-backed toggle either: discovery reports distance as 0, so it
///    would govern a number that always reads zero.
///
/// Anything with a server consequence belongs on `User.preferences`, not here.
class AppSettings {
  final ThemeMode themeMode;

  const AppSettings({this.themeMode = ThemeMode.system});

  AppSettings copyWith({ThemeMode? themeMode}) {
    return AppSettings(themeMode: themeMode ?? this.themeMode);
  }
}
