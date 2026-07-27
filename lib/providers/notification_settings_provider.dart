import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/notification_settings.dart';
import 'package:flame/services/notification_settings_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

/// Provides the notification settings service. Overridable in tests.
final notificationSettingsServiceProvider =
    Provider<NotificationSettingsService>(
        (ref) => NotificationSettingsService());

final notificationSettingsProvider = StateNotifierProvider<
    NotificationSettingsNotifier, AsyncValue<NotificationSettings>>((ref) {
  return NotificationSettingsNotifier(
    ref.watch(notificationSettingsServiceProvider),
  );
});

class NotificationSettingsNotifier
    extends StateNotifier<AsyncValue<NotificationSettings>> {
  final NotificationSettingsService _service;

  NotificationSettingsNotifier(this._service)
      : super(const AsyncValue.loading());

  /// Loads the notification settings from the service.
  Future<void> load() async {
    state = const AsyncValue.loading();
    final result = await _service.getSettings();
    if (result.success && result.data != null) {
      state = AsyncValue.data(result.data!);
    } else {
      state = AsyncValue.error(
        result.error ?? 'Failed to load notification settings',
        StackTrace.current,
      );
    }
  }

  Future<bool> setEnabled(bool value) => _update(
        (s) => s.copyWith(enabled: value),
        () => _service.updateSettings(enabled: value),
      );

  Future<bool> setChatMessages(bool value) => _update(
        (s) => s.copyWith(chatMessages: value),
        () => _service.updateSettings(chatMessages: value),
      );

  Future<bool> setMatches(bool value) => _update(
        (s) => s.copyWith(matches: value),
        () => _service.updateSettings(matches: value),
      );

  /// Optimistically applies [optimistic] to the current state, calls
  /// [request], and reconciles with the returned settings on success.
  /// Reverts to the previous state on failure.
  Future<bool> _update(
    NotificationSettings Function(NotificationSettings) optimistic,
    Future<ServiceResult<NotificationSettings>> Function() request,
  ) async {
    final previous = state.valueOrNull;
    if (previous == null) return false;

    state = AsyncValue.data(optimistic(previous));

    final result = await request();
    if (result.success && result.data != null) {
      state = AsyncValue.data(result.data!);
      return true;
    }

    state = AsyncValue.data(previous);
    return false;
  }
}
