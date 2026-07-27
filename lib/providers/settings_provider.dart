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

  void toggleShowOnlineStatus() {
    state = state.copyWith(showOnlineStatus: !state.showOnlineStatus);
  }

  void toggleShowDistance() {
    state = state.copyWith(showDistance: !state.showDistance);
  }

  void setDiscoveryEnabled(bool enabled) {
    state = state.copyWith(discoveryEnabled: enabled);
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

class AppSettings {
  final ThemeMode themeMode;
  final bool showOnlineStatus;
  final bool showDistance;
  final bool discoveryEnabled;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.showOnlineStatus = true,
    this.showDistance = true,
    this.discoveryEnabled = true,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? showOnlineStatus,
    bool? showDistance,
    bool? discoveryEnabled,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      showDistance: showDistance ?? this.showDistance,
      discoveryEnabled: discoveryEnabled ?? this.discoveryEnabled,
    );
  }
}
