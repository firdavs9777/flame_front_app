import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/push/push_permission.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/notification_settings.dart';
import 'package:flame/providers/notification_settings_provider.dart';
import 'package:flame/providers/push_provider.dart';
import 'package:flame/screens/settings/notification_settings_screen.dart';
import 'package:flame/services/notification_settings_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

class _Settings extends NotificationSettingsService {
  @override
  Future<ServiceResult<NotificationSettings>> getSettings() async =>
      ServiceResult.success(const NotificationSettings(
        enabled: true,
        chatMessages: true,
        matches: true,
      ));
}

/// Reports a fixed status without a platform channel.
class _Permission implements PushPermission {
  _Permission(this._status);

  final PushPermissionStatus _status;
  int openedSettings = 0;

  @override
  Future<PushPermissionStatus> status() async => _status;

  @override
  Future<void> openSystemSettings() async => openedSettings++;
}

Widget _wrap(_Permission permission) => ProviderScope(
      overrides: [
        notificationSettingsServiceProvider.overrideWithValue(_Settings()),
        pushPermissionProvider.overrideWithValue(permission),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NotificationSettingsScreen(),
      ),
    );

SwitchListTile _tile(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(find.byKey(Key(key)));

const _pushSwitches = [
  'notif_all',
  'notif_chat_messages',
  'notif_matches',
  'notif_reminders_push',
  'notif_promotions_push',
];

void main() {
  testWidgets('warns and disables every push switch when the OS says no',
      (tester) async {
    // The bug this exists to prevent: the screen showing five confident
    // switches while the operating system silently drops everything.
    await tester.pumpWidget(_wrap(_Permission(PushPermissionStatus.denied)));
    await tester.pumpAndSettle();

    expect(find.text('Notifications are turned off'), findsOneWidget);

    for (final key in _pushSwitches) {
      expect(_tile(tester, key).onChanged, isNull,
          reason: '$key must not pretend to work while the OS blocks push');
    }
  });

  testWidgets('leaves EMAIL switches alone when push is blocked',
      (tester) async {
    // Email arrives regardless of what this device allows. Disabling it here
    // would repeat the same mistake pointing the other way.
    await tester.pumpWidget(_wrap(_Permission(PushPermissionStatus.denied)));
    await tester.pumpAndSettle();

    // The banner plus seven switches overflow the 600px test surface, and the
    // list builds lazily — the email tiles do not exist until scrolled to.
    for (final key in ['notif_reminders_email', 'notif_promotions_email']) {
      await tester.scrollUntilVisible(find.byKey(Key(key)), 120);
      await tester.pumpAndSettle();
      expect(_tile(tester, key).onChanged, isNotNull,
          reason: '$key is email — push permission must not touch it');
    }
  });

  testWidgets('no banner when notifications are authorized', (tester) async {
    await tester
        .pumpWidget(_wrap(_Permission(PushPermissionStatus.authorized)));
    await tester.pumpAndSettle();

    expect(find.text('Notifications are turned off'), findsNothing);
    expect(_tile(tester, 'notif_all').onChanged, isNotNull);
    expect(_tile(tester, 'notif_chat_messages').onChanged, isNotNull);
  });

  testWidgets('provisional counts as working — they do arrive', (tester) async {
    // iOS quiet delivery. The notifications land in the notification centre
    // without alerting, so warning that push is off would be false.
    await tester
        .pumpWidget(_wrap(_Permission(PushPermissionStatus.provisional)));
    await tester.pumpAndSettle();

    expect(find.text('Notifications are turned off'), findsNothing);
    expect(_tile(tester, 'notif_chat_messages').onChanged, isNotNull);
  });

  testWidgets('stays quiet when the status cannot be read', (tester) async {
    // Firebase not initialised, or a platform with no such concept. A false
    // warning is worse than none.
    await tester.pumpWidget(_wrap(_Permission(PushPermissionStatus.unknown)));
    await tester.pumpAndSettle();

    expect(find.text('Notifications are turned off'), findsNothing);
    expect(_tile(tester, 'notif_all').onChanged, isNotNull);
  });

  testWidgets('the banner action opens the system settings page',
      (tester) async {
    final permission = _Permission(PushPermissionStatus.denied);
    await tester.pumpWidget(_wrap(permission));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notif_open_system_settings')));
    await tester.pumpAndSettle();

    expect(permission.openedSettings, 1);
  });
}
