import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/chat_provider.dart';
import 'package:flame/screens/chat/chat_attachments.dart';
import 'package:flame/screens/chat/widgets/attachment_modal.dart';
import 'package:flame/screens/chat/widgets/chat_input.dart';
import 'package:flame/services/chat_service.dart';

// The media backend shipped and the message bubble already renders image and
// video messages — but nothing in the app could SEND one. The four senders on
// ConversationsNotifier had zero callers, because the only attachment UI hung
// off ChatV2Screen, which nothing navigated to. These tests pin the wiring that
// closes that gap.

/// Records which sender was called with what, so the routing can be checked
/// without a network or a platform picker.
class _RecordingNotifier extends ConversationsNotifier {
  _RecordingNotifier() : super(ChatService());

  final calls = <String>[];
  String? lastConversationId;
  File? lastFile;
  String? lastReplyToId;
  String? failWith;

  /// Mirrors the real notifier's contract: exactly one of message or error.
  SendResult _outcome() => failWith == null
      ? SendResult.sent(Message.fromJson({
          'id': 'sent-1',
          'sender_id': 'me',
          'text': '',
          'created_at': '2026-08-18T10:00:00.000Z',
        }))
      : SendResult.failed(failWith!);

  @override
  Future<SendResult> sendImageMessage(
    String conversationId,
    File image, {
    String? replyToId,
  }) async {
    calls.add('image');
    lastConversationId = conversationId;
    lastFile = image;
    lastReplyToId = replyToId;
    return _outcome();
  }

  @override
  Future<SendResult> sendVideoMessage(
    String conversationId,
    File video, {
    int? duration,
    String? replyToId,
  }) async {
    calls.add('video');
    lastConversationId = conversationId;
    lastFile = video;
    lastReplyToId = replyToId;
    return _outcome();
  }
}

void main() {
  group('sendAttachment routing', () {
    test('gallery and camera both go to the image sender', () async {
      for (final kind in [ChatAttachmentKind.gallery, ChatAttachmentKind.camera]) {
        final n = _RecordingNotifier();

        await sendAttachment(
          kind: kind,
          notifier: n,
          conversationId: 'c1',
          file: File('/tmp/x.jpg'),
        );

        expect(n.calls, ['image'],
            reason: '$kind is still a photo — the source differs, not the kind');
      }
    });

    test('video goes to the video sender', () async {
      final n = _RecordingNotifier();

      await sendAttachment(
        kind: ChatAttachmentKind.video,
        notifier: n,
        conversationId: 'c1',
        file: File('/tmp/x.mp4'),
      );

      expect(n.calls, ['video']);
    });

    test('the conversation, file and reply target are passed through', () async {
      final n = _RecordingNotifier();
      final f = File('/tmp/photo.jpg');

      await sendAttachment(
        kind: ChatAttachmentKind.gallery,
        notifier: n,
        conversationId: 'conv-42',
        file: f,
        replyToId: 'msg-7',
      );

      expect(n.lastConversationId, 'conv-42');
      expect(n.lastFile, same(f));
      expect(n.lastReplyToId, 'msg-7',
          reason: 'replying with a photo must keep the reply target');
    });

    test('a successful send hands back the created message', () async {
      final n = _RecordingNotifier();

      final result = await sendAttachment(
        kind: ChatAttachmentKind.gallery,
        notifier: n,
        conversationId: 'c1',
        file: File('/tmp/x.jpg'),
      );

      expect(result.ok, isTrue);
      expect(result.message?.id, 'sent-1',
          reason: 'the caller appends this instead of refetching the page');
      expect(result.error, isNull);
    });

    test('an error from the sender is returned, not swallowed', () async {
      final n = _RecordingNotifier()..failWith = 'upload failed';

      final result = await sendAttachment(
        kind: ChatAttachmentKind.gallery,
        notifier: n,
        conversationId: 'c1',
        file: File('/tmp/x.jpg'),
      );

      expect(result.ok, isFalse);
      expect(result.error, 'upload failed',
          reason: 'the caller shows this to the user; swallowing it fails silently');
      expect(result.message, isNull,
          reason: 'a failed send must not hand back a message');
    });
  });

  group('AttachmentModal', () {
    Future<void> pump(WidgetTester tester, {VoidCallback? onTap}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttachmentModal(onPick: (_) => onTap?.call()),
          ),
        ),
      );
    }

    testWidgets('offers only the kinds the backend actually accepts', (tester) async {
      await pump(tester);

      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Video'), findsOneWidget);

      // GIF and Sticker had no backend — all five sticker endpoints 404 by
      // design, and there is no GIF endpoint at all. Offering them would be a
      // dead button, which is exactly what ChatInput's text-only comment was
      // guarding against.
      expect(find.text('GIF'), findsNothing);
      expect(find.text('Sticker'), findsNothing);
      expect(find.text('Voice'), findsNothing,
          reason: 'voice needs a recorder UI that does not exist yet');
    });

    testWidgets('reports the kind that was tapped', (tester) async {
      final picked = <ChatAttachmentKind>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AttachmentModal(onPick: picked.add)),
        ),
      );

      await tester.tap(find.text('Camera'));
      await tester.pump();

      expect(picked, [ChatAttachmentKind.camera]);
    });
  });

  group('ChatInput', () {
    Widget host({VoidCallback? onAttach}) => MaterialApp(
      home: Scaffold(
        body: ChatInput(
          controller: TextEditingController(),
          isSending: false,
          onSend: () {},
          onAttach: onAttach,
        ),
      ),
    );

    testWidgets('shows an attach button and fires it', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(onAttach: () => taps++));

      final button = find.byIcon(Icons.add_circle_outline);
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('hides the attach button when there is no handler', (tester) async {
      // Chat can be flag-gated off; a composer with no handler must not render
      // an affordance that does nothing.
      await tester.pumpWidget(host());

      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
    });

    testWidgets('the attach button is disabled while a send is in flight', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              controller: TextEditingController(),
              isSending: true,
              onSend: () {},
              onAttach: () => taps++,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();

      expect(taps, 0, reason: 'a second upload while one is uploading is a mistake');
    });
  });
}
