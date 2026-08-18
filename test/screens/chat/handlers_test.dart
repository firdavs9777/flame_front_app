import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/chat_provider.dart';
import 'package:flame/screens/chat/conversation/handlers/composer_actions.dart';
import 'package:flame/screens/chat/conversation/handlers/thread_actions.dart';
import 'package:flame/screens/chat/state/message_thread_provider.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

class _RecordingChatService extends ChatService {
  final List<String> sent = [];
  bool failSend = false;
  bool failPin = false;
  bool failMute = false;
  List<PinnedMessage> pins = const [];

  @override
  Future<ServiceResult<Message>> sendMessage(
    String conversationId,
    String text, {
    MessageType type = MessageType.text,
    String? replyToId,
  }) async {
    if (failSend) return ServiceResult.failure('offline');
    sent.add(text);
    return ServiceResult.success(Message.fromJson({
      'id': 'srv-${sent.length}',
      'sender_id': 'me',
      'text': text,
      'created_at': '2026-08-18T10:00:00.000Z',
    }));
  }

  @override
  Future<ServiceResult<MessagesResult>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
    String? before,
  }) async =>
      ServiceResult.success(MessagesResult(messages: [], hasMore: false));

  @override
  Future<ServiceResult<List<PinnedMessage>>> getPinnedMessages(String id) async =>
      ServiceResult.success(pins);

  @override
  Future<ServiceResult<List<PinnedMessage>>> pinMessage(
      String conversationId, String messageId) async {
    if (failPin) return ServiceResult.failure('nope');
    return ServiceResult.success([
      PinnedMessage(
        messageId: messageId,
        content: 'pinned',
        pinnedBy: 'me',
        pinnedAt: DateTime(2026, 8, 18),
      ),
    ]);
  }

  @override
  Future<ServiceResult<void>> unpinMessage(
      String conversationId, String messageId) async {
    if (failPin) return ServiceResult.failure('nope');
    return ServiceResult.success(null);
  }

  @override
  Future<ServiceResult<void>> muteConversation(String id,
      {int? durationHours}) async {
    if (failMute) return ServiceResult.failure('nope');
    return ServiceResult.success(null);
  }

  @override
  Future<ServiceResult<void>> unmuteConversation(String id) async {
    if (failMute) return ServiceResult.failure('nope');
    return ServiceResult.success(null);
  }
}

/// Pumps a Consumer so real WidgetRef and BuildContext are available, without
/// building any part of the chat screen.
class _Harness {
  late WidgetRef ref;
  late BuildContext context;
}

Future<_Harness> harnessWith(WidgetTester tester, ChatService service) async {
  final h = _Harness();
  await tester.pumpWidget(ProviderScope(
    overrides: [chatServiceProvider.overrideWithValue(service)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Consumer(builder: (context, ref, _) {
        h.ref = ref;
        h.context = context;
        // Watch the thread the way the real screen does. messageThreadProvider
        // is autoDispose, so a handler that only `read`s it would be talking to
        // a notifier Riverpod has already torn down — which is exactly what
        // happens if a caller forgets to watch.
        ref.watch(messageThreadProvider('c1'));
        return const Scaffold(body: SizedBox());
      }),
    ),
  ));
  await tester.pumpAndSettle();
  return h;
}

void main() {
  group('handleSendText', () {
    testWidgets('clears the composer and appends to the thread on success',
        (tester) async {
      final service = _RecordingChatService();
      final h = await harnessWith(tester, service);
      final controller = TextEditingController(text: 'hello');
      Message? replying = Message.fromJson({
        'id': 'r1', 'sender_id': 'u2', 'text': 'q',
        'created_at': '2026-08-18T09:00:00.000Z',
      });
      var sending = false;
      var sentCallbacks = 0;

      await handleSendText(
        context: h.context,
        ref: h.ref,
        conversationId: 'c1',
        controller: controller,
        replyingTo: replying,
        setReplyingTo: (m) => replying = m,
        setSending: (v) => sending = v,
        onSent: () => sentCallbacks++,
      );

      expect(service.sent, ['hello']);
      expect(controller.text, isEmpty);
      expect(sending, isFalse);
      expect(replying, isNull);
      expect(sentCallbacks, 1);
      expect(
          h.ref.read(messageThreadProvider('c1')).messages.single.id, 'srv-1');
    });

    testWidgets('restores text and reply target on failure', (tester) async {
      final service = _RecordingChatService()..failSend = true;
      final h = await harnessWith(tester, service);
      final controller = TextEditingController(text: 'hello');
      final original = Message.fromJson({
        'id': 'r1', 'sender_id': 'u2', 'text': 'q',
        'created_at': '2026-08-18T09:00:00.000Z',
      });
      Message? replying = original;
      var sentCallbacks = 0;

      await handleSendText(
        context: h.context,
        ref: h.ref,
        conversationId: 'c1',
        controller: controller,
        replyingTo: replying,
        setReplyingTo: (m) => replying = m,
        setSending: (_) {},
        onSent: () => sentCallbacks++,
      );

      expect(controller.text, 'hello',
          reason: 'a failed send must not eat what the user typed');
      expect(controller.selection.baseOffset, 'hello'.length);
      expect(replying, original,
          reason: 'nor quietly drop what they were replying to');
      expect(sentCallbacks, 0);
    });

    testWidgets('ignores whitespace-only input', (tester) async {
      final service = _RecordingChatService();
      final h = await harnessWith(tester, service);
      final controller = TextEditingController(text: '   ');

      await handleSendText(
        context: h.context,
        ref: h.ref,
        conversationId: 'c1',
        controller: controller,
        replyingTo: null,
        setReplyingTo: (_) {},
        setSending: (_) {},
        onSent: () {},
      );

      expect(service.sent, isEmpty);
    });
  });

  group('handleSendSticker', () {
    testWidgets('sends the emoji as the message text', (tester) async {
      final service = _RecordingChatService();
      final h = await harnessWith(tester, service);

      await handleSendSticker(
        context: h.context,
        ref: h.ref,
        conversationId: 'c1',
        emoji: '🔥',
        replyingTo: null,
        setReplyingTo: (_) {},
        setSending: (_) {},
        onSent: () {},
      );

      expect(service.sent, ['🔥']);
    });
  });

  group('thread actions', () {
    testWidgets('handleLoadPinned returns an empty list on failure',
        (tester) async {
      final service = _RecordingChatService();
      final h = await harnessWith(tester, service);

      final pins = await handleLoadPinned(ref: h.ref, conversationId: 'c1');

      expect(pins, isEmpty);
    });

    testWidgets('handlePin replaces the list with the server view',
        (tester) async {
      final service = _RecordingChatService();
      final h = await harnessWith(tester, service);

      final pins = await handlePin(
        context: h.context,
        ref: h.ref,
        conversationId: 'c1',
        messageId: 'm1',
        current: const [],
      );

      expect(pins.single.messageId, 'm1');
    });

    testWidgets('a failed pin returns the list unchanged', (tester) async {
      final service = _RecordingChatService()..failPin = true;
      final h = await harnessWith(tester, service);
      final existing = [
        PinnedMessage(
          messageId: 'keep',
          content: 'x',
          pinnedBy: 'me',
          pinnedAt: DateTime(2026, 8, 18),
        ),
      ];

      final pins = await handlePin(
        context: h.context,
        ref: h.ref,
        conversationId: 'c1',
        messageId: 'm1',
        current: existing,
      );

      expect(pins, existing);
    });

    testWidgets('handleUnpin removes only the target', (tester) async {
      final service = _RecordingChatService();
      final h = await harnessWith(tester, service);
      final existing = [
        PinnedMessage(
            messageId: 'a', content: 'x', pinnedBy: 'me',
            pinnedAt: DateTime(2026, 8, 18)),
        PinnedMessage(
            messageId: 'b', content: 'y', pinnedBy: 'me',
            pinnedAt: DateTime(2026, 8, 18)),
      ];

      final pins = await handleUnpin(
        context: h.context,
        ref: h.ref,
        conversationId: 'c1',
        messageId: 'a',
        current: existing,
      );

      expect(pins.map((p) => p.messageId), ['b']);
    });

    testWidgets('handleToggleMute reports the requested state on success',
        (tester) async {
      final h = await harnessWith(tester, _RecordingChatService());

      expect(
          await handleToggleMute(
              context: h.context, ref: h.ref,
              conversationId: 'c1', wasMuted: false),
          isTrue);
      expect(
          await handleToggleMute(
              context: h.context, ref: h.ref,
              conversationId: 'c1', wasMuted: true),
          isFalse);
    });

    testWidgets('handleToggleMute reports the previous state on failure',
        (tester) async {
      final h = await harnessWith(
          tester, _RecordingChatService()..failMute = true);

      expect(
          await handleToggleMute(
              context: h.context, ref: h.ref,
              conversationId: 'c1', wasMuted: false),
          isFalse,
          reason: 'the caller must not show muted when the server refused');
    });
  });
}
