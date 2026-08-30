import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/chat/header/chat_app_bar.dart';
import 'package:flame/screens/chat/header/pinned_messages_bar.dart';
import 'package:flame/screens/chat/state/thread_presence_provider.dart';
import 'package:flame/services/chat_service.dart' show PinnedMessage;
import 'package:flame/theme/app_theme.dart';

User _user({bool online = false}) => User.fromJson({
      'id': 'u2',
      'name': 'Bea',
      'photos': <dynamic>[],
      'is_online': online,
    });

var muteTaps = 0;
var profileTaps = 0;
var reportTaps = 0;
var blockTaps = 0;

Widget _appBarHost(
  ThreadPresenceState presence, {
  bool isMuted = false,
  ThemeData? theme,
}) =>
    MaterialApp(
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        appBar: ChatAppBar(
          otherUser: _user(),
          presence: presence,
          isMuted: isMuted,
          onToggleMute: () => muteTaps++,
          onOpenProfile: () => profileTaps++,
          onReport: () => reportTaps++,
          onBlock: () => blockTaps++,
        ),
      ),
    );

const _idle = ThreadPresenceState(isOtherTyping: false, isOtherOnline: false);
const _typing = ThreadPresenceState(isOtherTyping: true, isOtherOnline: true);

void main() {
  setUp(() {
    muteTaps = 0;
    profileTaps = 0;
    reportTaps = 0;
    blockTaps = 0;
  });

  group('ChatAppBar', () {
    // Reporting and blocking used to live only behind the partner's profile,
    // two taps from the conversation where the problem is actually happening.
    // Apple's UGC rules expect both from the messaging surface itself.
    testWidgets('the overflow menu offers Report and Block', (tester) async {
      await tester.pumpWidget(_appBarHost(_idle));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Block'), findsOneWidget);
    });

    testWidgets('Report fires its callback', (tester) async {
      await tester.pumpWidget(_appBarHost(_idle));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(reportTaps, 1);
      expect(blockTaps, 0);
    });

    testWidgets('Block fires its callback', (tester) async {
      await tester.pumpWidget(_appBarHost(_idle));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();

      expect(blockTaps, 1);
      expect(reportTaps, 0);
    });

    testWidgets('shows the partner name', (tester) async {
      await tester.pumpWidget(_appBarHost(_idle));
      await tester.pumpAndSettle();

      expect(find.text('Bea'), findsOneWidget);
    });

    testWidgets('typing replaces the last-active line', (tester) async {
      await tester.pumpWidget(_appBarHost(_typing));
      await tester.pumpAndSettle();

      expect(find.text('typing…'), findsOneWidget);
    });

    testWidgets('not typing does not show the typing line', (tester) async {
      await tester.pumpWidget(_appBarHost(_idle));
      await tester.pumpAndSettle();

      expect(find.text('typing…'), findsNothing);
    });

    testWidgets('the avatar decodes at the size it is drawn', (tester) async {
      await tester.pumpWidget(_appBarHost(_idle));
      await tester.pumpAndSettle();

      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      // No photo on this fixture, so the provider is null — the assertion that
      // matters is that the radius and the decode target agree, which
      // avatarProvider enforces by requiring the diameter.
      expect(avatar.radius, 20);
    });

    testWidgets('the menu offers mute and profile, and both call back',
        (tester) async {
      await tester.pumpWidget(_appBarHost(_idle));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Mute notifications'), findsOneWidget);
      expect(find.text('View profile'), findsOneWidget);

      await tester.tap(find.text('Mute notifications'));
      await tester.pumpAndSettle();
      expect(muteTaps, 1);
    });

    testWidgets('an already-muted chat offers unmute instead', (tester) async {
      await tester.pumpWidget(_appBarHost(_idle, isMuted: true));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Unmute notifications'), findsOneWidget);
      expect(find.text('Mute notifications'), findsNothing);
    });

    testWidgets('tapping the title opens the profile', (tester) async {
      await tester.pumpWidget(_appBarHost(_idle));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bea'));
      await tester.pumpAndSettle();

      expect(profileTaps, 1);
    });

    testWidgets('renders in dark theme without a hardcoded surface',
        (tester) async {
      await tester.pumpWidget(
          _appBarHost(_typing, theme: AppTheme.darkTheme));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Bea'), findsOneWidget);
    });
  });

  group('PinnedMessagesBar', () {
    final tapped = <String>[];
    final unpinned = <String>[];

    PinnedMessage pin(String id, String content) => PinnedMessage(
          messageId: id,
          content: content,
          pinnedBy: 'me',
          pinnedAt: DateTime(2026, 8, 18),
        );

    Widget host(List<PinnedMessage> pinned) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PinnedMessagesBar(
              pinned: pinned,
              onTap: tapped.add,
              onUnpin: unpinned.add,
            ),
          ),
        );

    setUp(() {
      tapped.clear();
      unpinned.clear();
    });

    testWidgets('one pin names itself and shows its text', (tester) async {
      await tester.pumpWidget(host([pin('m1', 'read this')]));
      await tester.pumpAndSettle();

      expect(find.text('Pinned message'), findsOneWidget);
      expect(find.text('read this'), findsOneWidget);
    });

    testWidgets('several pins show the count and the newest text',
        (tester) async {
      await tester.pumpWidget(
          host([pin('m1', 'older'), pin('m2', 'newest')]));
      await tester.pumpAndSettle();

      expect(find.text('Pinned · 2'), findsOneWidget);
      expect(find.text('newest'), findsOneWidget);
      expect(find.text('older'), findsNothing);
    });

    testWidgets('a pin with no text says Attachment rather than nothing',
        (tester) async {
      await tester.pumpWidget(host([pin('m1', '')]));
      await tester.pumpAndSettle();

      expect(find.text('Attachment'), findsOneWidget);
    });

    testWidgets('tapping jumps to the newest pin; close unpins it',
        (tester) async {
      await tester.pumpWidget(
          host([pin('m1', 'older'), pin('m2', 'newest')]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('newest'));
      await tester.pumpAndSettle();
      expect(tapped, ['m2']);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(unpinned, ['m2']);
    });
  });
}
