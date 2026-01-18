import 'package:flutter_riverpod/flutter_riverpod.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings());

  void toggleDarkMode() {
    state = state.copyWith(isDarkMode: !state.isDarkMode);
  }

  void toggleNotifications() {
    state = state.copyWith(notificationsEnabled: !state.notificationsEnabled);
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

class AppSettings {
  final bool isDarkMode;
  final bool notificationsEnabled;
  final bool showOnlineStatus;
  final bool showDistance;
  final bool discoveryEnabled;

  const AppSettings({
    this.isDarkMode = false,
    this.notificationsEnabled = true,
    this.showOnlineStatus = true,
    this.showDistance = true,
    this.discoveryEnabled = true,
  });

  AppSettings copyWith({
    bool? isDarkMode,
    bool? notificationsEnabled,
    bool? showOnlineStatus,
    bool? showDistance,
    bool? discoveryEnabled,
  }) {
    return AppSettings(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      showDistance: showDistance ?? this.showDistance,
      discoveryEnabled: discoveryEnabled ?? this.discoveryEnabled,
    );
  }
}
