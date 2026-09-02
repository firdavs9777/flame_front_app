import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/notification_settings.dart';
import 'package:flame/services/notification_settings_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;
import 'package:flame/providers/notification_settings_provider.dart';

class _FakeNotificationSettingsService extends NotificationSettingsService {
  bool getCalled = false;
  bool updateCalled = false;
  bool? lastEnabled;
  bool? lastChatMessages;
  bool? lastMatches;
  bool? lastPromotions;
  bool? lastReengagement;
  bool getSucceeds = true;
  bool updateSucceeds = true;
  NotificationSettings settings = const NotificationSettings(
    enabled: true,
    chatMessages: true,
    matches: true,
  );

  @override
  Future<ServiceResult<NotificationSettings>> getSettings() async {
    getCalled = true;
    return getSucceeds
        ? ServiceResult.success(settings)
        : ServiceResult.failure('Failed to load notification settings');
  }

  @override
  Future<ServiceResult<NotificationSettings>> updateSettings({
    bool? enabled,
    bool? chatMessages,
    bool? matches,
    bool? promotions,
    bool? reengagement,
    bool? promotionsPush,
    bool? reengagementPush,
  }) async {
    updateCalled = true;
    lastEnabled = enabled;
    lastChatMessages = chatMessages;
    lastMatches = matches;
    lastPromotions = promotions;
    lastReengagement = reengagement;

    if (!updateSucceeds) {
      return ServiceResult.failure('Failed to update notification settings');
    }

    settings = settings.copyWith(
      enabled: enabled,
      chatMessages: chatMessages,
      matches: matches,
      promotions: promotions,
      reengagement: reengagement,
    );
    return ServiceResult.success(settings);
  }
}

void main() {
  test('load() maps getSettings() into state as data', () async {
    final fake = _FakeNotificationSettingsService()
      ..settings = const NotificationSettings(
        enabled: true,
        chatMessages: false,
        matches: true,
      );
    final n = NotificationSettingsNotifier(fake);

    await n.load();

    expect(fake.getCalled, isTrue);
    expect(n.state.value!.enabled, true);
    expect(n.state.value!.chatMessages, false);
    expect(n.state.value!.matches, true);
  });

  test('load() failure surfaces an AsyncError and does not throw', () async {
    final fake = _FakeNotificationSettingsService()..getSucceeds = false;
    final n = NotificationSettingsNotifier(fake);

    await n.load();

    expect(n.state, isA<AsyncError>());
    expect(n.state.valueOrNull, isNull);
  });

  test('setChatMessages(false) calls the service and updates state from the response',
      () async {
    final fake = _FakeNotificationSettingsService();
    final n = NotificationSettingsNotifier(fake);
    await n.load();

    final ok = await n.setChatMessages(false);

    expect(ok, isTrue);
    expect(fake.updateCalled, isTrue);
    expect(fake.lastChatMessages, false);
    expect(fake.lastEnabled, isNull);
    expect(fake.lastMatches, isNull);
    expect(n.state.value!.chatMessages, false);
  });

  test('setChatMessages optimistically updates before the request resolves',
      () async {
    final fake = _FakeNotificationSettingsService();
    final n = NotificationSettingsNotifier(fake);
    await n.load();

    final future = n.setChatMessages(false);
    // Immediately after calling (before awaiting), the optimistic value
    // should already be reflected in state.
    expect(n.state.value!.chatMessages, false);

    await future;
  });

  test('setEnabled(false) failure reverts to the previous state and returns false',
      () async {
    final fake = _FakeNotificationSettingsService()..updateSucceeds = false;
    final n = NotificationSettingsNotifier(fake);
    await n.load();

    final ok = await n.setEnabled(false);

    expect(ok, isFalse);
    expect(fake.updateCalled, isTrue);
    expect(n.state.value!.enabled, true);
  });

  test('setMatches(false) failure reverts matches to previous value', () async {
    final fake = _FakeNotificationSettingsService()..updateSucceeds = false;
    final n = NotificationSettingsNotifier(fake);
    await n.load();

    final ok = await n.setMatches(false);

    expect(ok, isFalse);
    expect(n.state.value!.matches, true);
  });
}
