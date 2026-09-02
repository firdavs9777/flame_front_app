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
  bool? lastPromotions;
  bool? lastReengagement;
  bool? lastPromotionsPush;
  bool? lastReengagementPush;
  bool getSucceeds = true;
  bool updateSucceeds = true;
  NotificationSettings settings = const NotificationSettings(
    enabled: true,
    chatMessages: true,
    matches: true,
    promotions: false,
    reengagement: true,
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
    lastPromotionsPush = promotionsPush;
    lastReengagementPush = reengagementPush;
    if (!updateSucceeds) {
      return ServiceResult.failure('Failed to update notification settings');
    }
    settings = settings.copyWith(
      enabled: enabled,
      chatMessages: chatMessages,
      matches: matches,
      promotions: promotions,
      reengagement: reengagement,
      promotionsPush: promotionsPush,
      reengagementPush: reengagementPush,
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
/// Looks a tile up by key.
///
/// "Promotions" and "Reminders" each appear twice — once under Push, once
/// under Email — so a title is no longer a unique handle.
SwitchListTile _tile(WidgetTester tester, String key) {
  return tester.widget<SwitchListTile>(find.byKey(Key(key)));
}

SwitchListTile _tileByTitle(WidgetTester tester, String title) {
  return tester.widgetList<SwitchListTile>(find.byType(SwitchListTile)).firstWhere(
        (t) => (t.title as Text).data == title,
      );
}

void main() {
  testWidgets('loads settings and renders the push switches', (tester) async {
    final fake = _FakeNotificationSettingsService()
      ..settings = const NotificationSettings(
        enabled: true,
        chatMessages: false,
        matches: true,
      );

    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    // Five now: the two email channels joined the three push ones. Asserting the
    // exact count rather than "at least three" is what caught this when the
    // screen grew, which is the point of counting at all.
    expect(find.byType(SwitchListTile), findsNWidgets(7));
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

  testWidgets('renders both channels, push and email', (tester) async {
    await tester.pumpWidget(_wrap(_FakeNotificationSettingsService()));
    await tester.pumpAndSettle();

    // Five switches now: three push, two email. Grouped under headings, because
    // "All notifications" governing the push three but not the email two is only
    // legible if the two groups are visibly separate.
    expect(find.byType(SwitchListTile), findsNWidgets(7));
    expect(_tile(tester, 'notif_promotions_email').value, false);
    expect(_tile(tester, 'notif_reminders_email').value, true);
    expect(find.text('Push notifications'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('the push master toggle does NOT disable the email switches',
      (tester) async {
    final fake = _FakeNotificationSettingsService()
      ..settings = const NotificationSettings(
        enabled: false,
        chatMessages: true,
        matches: true,
        promotions: true,
        reengagement: true,
      );

    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    // Push children are correctly gated...
    expect(_tileByTitle(tester, 'Chat messages').onChanged, isNull);
    expect(_tileByTitle(tester, 'New matches').onChanged, isNull);
    // ...and email is a DIFFERENT CHANNEL. A push toggle silently switching off
    // someone's email would be wrong, and it is the kind of thing that looks
    // right in a screenshot.
    expect(_tile(tester, 'notif_promotions_email').onChanged, isNotNull);
    expect(_tile(tester, 'notif_reminders_email').onChanged, isNotNull);
  });

  testWidgets('promotions can be switched ON', (tester) async {
    final fake = _FakeNotificationSettingsService();
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    // The whole reason this switch has to exist: promotions defaults to false,
    // so without a way to turn it on the campaign job correctly mails nobody.
    await tester.ensureVisible(find.byKey(const Key('notif_promotions_email')));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidget(_tile(tester, 'notif_promotions_email')));
    await tester.pumpAndSettle();

    expect(fake.lastPromotions, true);
  });

  testWidgets('reminders can be switched off from here, not only from the email',
      (tester) async {
    final fake = _FakeNotificationSettingsService();
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('notif_reminders_email')));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidget(_tile(tester, 'notif_reminders_email')));
    await tester.pumpAndSettle();

    expect(fake.lastReengagement, false);
  });

  testWidgets('a failed email update reverts the switch and says so',
      (tester) async {
    final fake = _FakeNotificationSettingsService()..updateSucceeds = false;
    await tester.pumpWidget(_wrap(fake));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('notif_promotions_email')));
    await tester.pumpAndSettle();
    await tester.tap(find.byWidget(_tile(tester, 'notif_promotions_email')));
    await tester.pumpAndSettle();

    expect(_tile(tester, 'notif_promotions_email').value, false,
        reason: 'an optimistic flip must revert when the server refuses');
    expect(find.text("Could not update notification settings"), findsOneWidget);
  });

  testWidgets('the title is localized, not a hardcoded English literal',
      (tester) async {
    // It was `const Text('Notifications')` — in a Settings screen the profile
    // and settings localization sweep was supposed to have covered.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationSettingsServiceProvider
            .overrideWithValue(_FakeNotificationSettingsService()),
      ],
      child: MaterialApp(
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NotificationSettingsScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('renders at double text scale without overflowing', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        notificationSettingsServiceProvider
            .overrideWithValue(_FakeNotificationSettingsService()),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: NotificationSettingsScreen(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
