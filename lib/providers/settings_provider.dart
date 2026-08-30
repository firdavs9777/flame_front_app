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

  /// Records the choice even when it matches what is already on screen.
  ///
  /// It used to return early on a no-op, which was harmless while the default
  /// was System — nobody's first tap could match it. With a dark default,
  /// tapping Dark stores nothing, so the difference between "we chose this for
  /// them" and "they chose it" is lost, and the next change of default would
  /// silently overrule someone who had actually picked.
  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode != state.themeMode) {
      state = state.copyWith(themeMode: mode);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  }
}

/// [value] is null when nobody has ever chosen, which is NOT the same as
/// having chosen System — so the two cannot share a branch. A stored 'system'
/// is a deliberate choice and has to survive a change of default.
ThemeMode _themeModeFromString(String? value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    case 'system':
      return ThemeMode.system;
    default:
      return kDefaultThemeMode;
  }
}

/// Dark, not System.
///
/// A deliberate look rather than a deference: the palette, the deck's card
/// shadows and the photo-forward layout were all built dark-first, and a
/// swipe deck sits better on a dark ground — the photos carry the colour and
/// nothing competes with them. Following the OS meant half the users never saw
/// the app the way it was designed.
///
/// It is a default, not a lock: Settings → Appearance still offers all three,
/// and an explicit System choice is honoured and persisted.
const ThemeMode kDefaultThemeMode = ThemeMode.dark;

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

  const AppSettings({this.themeMode = kDefaultThemeMode});

  AppSettings copyWith({ThemeMode? themeMode}) {
    return AppSettings(themeMode: themeMode ?? this.themeMode);
  }
}
