import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/notification_settings.dart';
import 'package:flame/services/notification_settings_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;
import 'package:flame/providers/notification_settings_provider.dart';
import 'package:flame/screens/settings/notification_settings_screen.dart';
import 'package:flame/l10n/gen/app_localizations.dart';

class _FakeNotificationSettingsService extends NotificationSettingsService {
  bool updateCalled = false;
  bool? lastEnabled;
  bool? lastChatMessages;
  bool? lastMatches;
  bool getSucceeds = true;
  bool updateSucceeds = true;
  NotificationSettings settings = const NotificationSettings(
    enabled: true,
    chatMessages: true,
    matches: true,
  );

  @override
  Future<ServiceResult<NotificationSettings>> getSettings() async {
    return getSucceeds
        ? ServiceResult.success(settings)
        : ServiceResult.failure('Failed to load notification settings');
  }

  @override
  Future<ServiceResult<NotificationSettings>> updateSettings({
    bool? enabled,
    bool? chatMessages,
    bool? matches,
  }) async {
    updateCalled = true;
    lastEnabled = enabled;
    lastChatMessages = chatMessages;
    lastMatches = matches;
    if (!updateSucceeds) {
      return ServiceResult.failure('Failed to update notification settings');
    }
    settings = settings.copyWith(
      enabled: enabled,
      chatMessages: chatMessages,
      matches: matches,
    );
    return ServiceResult.success(settings);
  }
}

Widget _wrap(_FakeNotificationSettingsService fake) {
  return ProviderScope(
    overrides: [
      notificationSettingsServiceProvider.overrideWithValue(fake),
    ],
    // The screen reads its labels from the ARBs now.
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const NotificationSettingsScreen(),
    ),
  );
}

/// Finds the SwitchListTile whose title reads [title].
SwitchListTile _tileByTitle(WidgetTester tester, String title) {
  return tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).firstWhere(
        (t) => (t.title as Text).data == title,
      );
}

void main() {
  testWidgets('loads settings and renders the three switches', (tester) async {
    final fake = _FakeNotificationSettingsService()
      ..settings = const NotificationSettings(
        enabled: true,
        chatMessages: false,
        matches: true,
      );

    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    expect(find.byType(SwitchListTile), findsNWidgets(3));
    expect(_tileByTitle(tester, 'All notifications').value, true);
    expect(_tileByTitle(tester, 'Chat messages').value, false);
    expect(_tileByTitle(tester, 'New matches').value, true);
  });

  testWidgets('renders an error state with a retry action on load failure',
      (tester) async {
    final fake = _FakeNotificationSettingsService()..getSucceeds = false;

    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Could not load notification settings'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('toggling a switch calls the service with only that field',
      (tester) async {
    final fake = _FakeNotificationSettingsService();

    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chat messages'));
    await tester.pumpAndSettle();

    expect(fake.updateCalled, isTrue);
    expect(fake.lastChatMessages, false);
    expect(fake.lastEnabled, isNull);
    expect(fake.lastMatches, isNull);
    expect(_tileByTitle(tester, 'Chat messages').value, false);
  });

  testWidgets('disabling all notifications disables the sub-toggles',
      (tester) async {
    final fake = _FakeNotificationSettingsService();

    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('All notifications'));
    await tester.pumpAndSettle();

    expect(_tileByTitle(tester, 'All notifications').value, false);
    // Sub-toggles are disabled (onChanged == null) while all-off.
    expect(_tileByTitle(tester, 'Chat messages').onChanged, isNull);
    expect(_tileByTitle(tester, 'New matches').onChanged, isNull);
  });

  testWidgets('shows a snackbar when an update fails', (tester) async {
    final fake = _FakeNotificationSettingsService()..updateSucceeds = false;

    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Chat messages'));
    await tester.pump(); // let the snackbar appear

    expect(
      find.text('Could not update notification settings'),
      findsOneWidget,
    );
  });
}
