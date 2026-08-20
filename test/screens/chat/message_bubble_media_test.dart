import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/chat/widgets/message_bubble.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';

// A photo is its own shape. Rendering one inside the text pill framed every
// image in `AppTheme.primaryColor` when you sent it and `context.fill` when you
// received it — a visible coloured border around the picture, which is what a
// user reported seeing.
//
// The second half of this is subtler and is why the fix is not one line: the
// timestamp and delivery tick colour themselves `context.onPrimary` when
// `isMe`, which is only correct BECAUSE the pill is `primaryColor`. Stickers
// were already bare, so an outgoing sticker's timestamp was already white on
// the page background — invisible in light mode. Making media bare without
// moving those colours would have spread that bug to every photo.
Message _media({
  required MessageType type,
  String content = 'https://example.com/p.jpg',
}) {
  return Message.fromJson({
    'id': 'm1',
    'sender_id': 'u1',
    'text': content,
    'message_type': type.name,
    'created_at': '2026-08-20T09:00:00.000Z',
    'status': 'sent',
  });
}

Widget _host(Widget child, {ThemeData? theme}) {
  return ProviderScope(
    child: MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      home: Scaffold(body: child),
    ),
  );
}

/// The bubble's own container, identified by the asymmetric corner radius only
/// it uses. Matching on the decoration rather than on widget order keeps this
/// from breaking every time the tree gains a wrapper.
Iterable<BoxDecoration> _bubbleDecorations(WidgetTester tester) {
  return tester
      .widgetList<Container>(find.byType(Container))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .where((d) {
        final r = d.borderRadius;
        return r is BorderRadius && r.topLeft == const Radius.circular(20);
      });
}

/// The colour the bubble drew `message.timeText` in.
///
/// Keyed off the message's own `timeText` rather than a guessed format —
/// `timeText` is relative ("2h", "3d"), so an earlier version of this helper
/// searched for a colon, found nothing, and returned null. Both assertions
/// using it passed against a null. Hence [expect]ing non-null at each call.
Color? _timestampColour(WidgetTester tester, Message message) {
  final finder = find.text(message.timeText);
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).style?.color;
}

void main() {
  group('media messages get no bubble fill', () {
    for (final type in [MessageType.image, MessageType.video, MessageType.gif]) {
      testWidgets('an outgoing ${type.name} is not framed in the brand colour',
          (tester) async {
        await tester.pumpWidget(_host(
          MessageBubble(message: _media(type: type), isMe: true),
        ));

        final fills = _bubbleDecorations(tester).map((d) => d.color).toList();
        expect(
          fills,
          isNot(contains(AppTheme.primaryColor)),
          reason: 'a photo framed in the brand colour is the reported bug',
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('an incoming ${type.name} is not framed in the fill colour',
          (tester) async {
        late Color fill;
        await tester.pumpWidget(_host(
          Builder(builder: (context) {
            fill = context.fill;
            return MessageBubble(message: _media(type: type), isMe: false);
          }),
        ));

        final fills = _bubbleDecorations(tester).map((d) => d.color).toList();
        expect(fills, isNot(contains(fill)));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('text messages keep their pill', (tester) async {
      await tester.pumpWidget(_host(
        MessageBubble(
          message: Message.fromJson({
            'id': 'm2',
            'sender_id': 'u1',
            'text': 'hello',
            'message_type': 'text',
            'created_at': '2026-08-20T09:00:00.000Z',
          }),
          isMe: true,
        ),
      ));

      // The pill is the whole reason a text message reads as a message.
      expect(
        _bubbleDecorations(tester).map((d) => d.color),
        contains(AppTheme.primaryColor),
      );
    });

    testWidgets('a voice message keeps its pill — a player needs a surface',
        (tester) async {
      await tester.pumpWidget(_host(
        MessageBubble(
          message: _media(
            type: MessageType.voice,
            content: 'https://example.com/a.m4a',
          ),
          isMe: true,
        ),
      ));

      expect(
        _bubbleDecorations(tester).map((d) => d.color),
        contains(AppTheme.primaryColor),
      );
    });
  });

  group('meta on a bare bubble sits on the page, not on the pill', () {
    testWidgets('an outgoing image timestamp is not onPrimary', (tester) async {
      final message = _media(type: MessageType.image);
      late Color onPrimary;
      late Color secondary;
      await tester.pumpWidget(_host(
        Builder(builder: (context) {
          onPrimary = context.onPrimary;
          secondary = context.secondaryText;
          return MessageBubble(
            message: message,
            isMe: true,
            isLastInGroup: true,
          );
        }),
      ));

      final colour = _timestampColour(tester, message);
      expect(colour, isNotNull, reason: 'the last bubble in a run shows a time');
      expect(
        colour,
        isNot(onPrimary),
        reason: 'white on the page background is invisible in light mode',
      );
      expect(colour, secondary);
    });

    testWidgets('an outgoing sticker timestamp is not onPrimary either',
        (tester) async {
      // Pre-existing instance of the same defect: stickers were already bare.
      final message = _media(type: MessageType.sticker, content: '🎉');
      late Color secondary;
      await tester.pumpWidget(_host(
        Builder(builder: (context) {
          secondary = context.secondaryText;
          return MessageBubble(
            message: message,
            isMe: true,
            isLastInGroup: true,
          );
        }),
      ));

      final colour = _timestampColour(tester, message);
      expect(colour, isNotNull);
      // Asserting equality, not `isNot(onPrimary)`: the code writes
      // `onPrimary.withValues(alpha: 0.7)`, so an inequality check against
      // full-alpha onPrimary passed while the bug was still there.
      expect(colour, secondary);
    });

    testWidgets('an outgoing text timestamp stays onPrimary', (tester) async {
      // It genuinely sits on the brand-coloured pill, so it must not move.
      final message = Message.fromJson({
        'id': 'm3',
        'sender_id': 'u1',
        'text': 'hello',
        'message_type': 'text',
        'created_at': '2026-08-20T09:00:00.000Z',
      });
      late Color onPrimary;
      await tester.pumpWidget(_host(
        Builder(builder: (context) {
          onPrimary = context.onPrimary;
          return MessageBubble(
            message: message,
            isMe: true,
            isLastInGroup: true,
          );
        }),
      ));

      final colour = _timestampColour(tester, message);
      expect(colour, isNotNull);
      expect(colour, onPrimary.withValues(alpha: 0.7));
    });

    testWidgets('a bare bubble renders in dark theme too', (tester) async {
      await tester.pumpWidget(_host(
        MessageBubble(
          message: _media(type: MessageType.image),
          isMe: true,
        ),
        theme: AppTheme.darkTheme,
      ));

      expect(tester.takeException(), isNull);
    });
  });

  // Reported as "image sizes are all different in the chat weird". Three causes,
  // all here: the box only ever *capped* the width, so a small photo drew small
  // and a tall one narrowed to fit the height cap; video and gif hardcoded a
  // different width from images; and the loading placeholder had no width at
  // all, so a bubble changed size the moment its photo arrived.
  group('every chat medium occupies the same width', () {
    for (final type in [MessageType.image, MessageType.gif, MessageType.video]) {
      testWidgets('a ${type.name} is exactly kChatMediaWidth wide',
          (tester) async {
        await tester.pumpWidget(_host(
          MessageBubble(message: _media(type: type), isMe: true),
        ));

        final box = find.byKey(const Key('chat-media'));
        expect(box, findsOneWidget, reason: 'every medium needs the shared box');
        expect(tester.getSize(box).width, kChatMediaWidth);
      });
    }

    testWidgets('an incoming and an outgoing photo are the same width',
        (tester) async {
      await tester.pumpWidget(_host(
        Column(
          children: [
            MessageBubble(message: _media(type: MessageType.image), isMe: true),
            MessageBubble(message: _media(type: MessageType.image), isMe: false),
          ],
        ),
      ));

      final widths = tester
          .widgetList(find.byKey(const Key('chat-media')))
          .map((w) => tester.getSize(find.byWidget(w)).width)
          .toSet();
      expect(widths, {kChatMediaWidth});
    });

    testWidgets('the loading placeholder is already the final width',
        (tester) async {
      // Nothing loads in a widget test, so what is measured here IS the
      // placeholder — which is the point: a placeholder narrower than the photo
      // makes the whole thread reflow as images arrive.
      await tester.pumpWidget(_host(
        MessageBubble(message: _media(type: MessageType.image), isMe: false),
      ));

      expect(
        tester.getSize(find.byKey(const Key('chat-media'))).width,
        kChatMediaWidth,
      );
    });

    testWidgets('a medium is height-capped rather than running away',
        (tester) async {
      await tester.pumpWidget(_host(
        MessageBubble(message: _media(type: MessageType.image), isMe: true),
      ));

      expect(
        tester.getSize(find.byKey(const Key('chat-media'))).height,
        lessThanOrEqualTo(kChatMediaMaxHeight),
      );
    });
  });
}
