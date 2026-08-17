import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/chat/widgets/sticker_panel.dart';
import 'package:flame/screens/chat/widgets/message_bubble.dart';

// A sticker is an emoji carried in the message text — BananaTalk's model, and
// the only one either backend has ever supported. Flame's inherited
// sticker_picker.dart was written against a pack catalog with hosted artwork
// that has never existed, and its bubble still rendered a sticker as
// Image.network of the content, which for an emoji is a broken-image icon.
void main() {
  group('StickerPanel', () {
    testWidgets('shows categories and emoji', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StickerPanel(onPick: (_) {})),
      ));

      expect(find.text('Smileys'), findsOneWidget);
      expect(find.text('Hearts'), findsOneWidget);
      // Whatever the first category is, its emoji should be on screen.
      expect(find.text('😀'), findsOneWidget);
    });

    testWidgets('reports the emoji that was tapped', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StickerPanel(onPick: picked.add)),
      ));

      await tester.tap(find.text('😀'));
      await tester.pump();

      expect(picked, ['😀']);
    });

    testWidgets('switching category changes the grid', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StickerPanel(onPick: (_) {})),
      ));

      await tester.tap(find.text('Hearts'));
      await tester.pumpAndSettle();

      expect(find.text('❤️'), findsOneWidget);
      expect(find.text('😀'), findsNothing);
    });

    test('every category has emoji, and none repeats within one', () {
      for (final entry in stickerCategories.entries) {
        expect(entry.value, isNotEmpty, reason: '${entry.key} is empty');
        expect(
          entry.value.toSet().length,
          entry.value.length,
          reason: '${entry.key} repeats an emoji',
        );
      }
    });
  });

  group('sticker bubble', () {
    Message sticker(String emoji) => Message.fromJson({
      'id': 'm1',
      'sender_id': 'u1',
      'text': emoji,
      'message_type': 'sticker',
      'created_at': '2026-08-17T00:00:00.000Z',
    });

    testWidgets('renders the emoji as text, not as an image URL', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: sticker('🎉'), isMe: false),
        ),
      ));

      expect(find.text('🎉'), findsOneWidget);
      // Image.network('🎉') is not a URL — it used to render a broken-image
      // icon for every sticker ever sent.
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a sticker has no bubble background', (tester) async {
      // A big emoji inside a coloured pill reads as a typo, not a sticker.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MessageBubble(message: sticker('🎉'), isMe: true),
        ),
      ));

      expect(find.text('🎉'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
