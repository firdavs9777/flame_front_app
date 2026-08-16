// Regression test for the bug B1 exists to fix: ChatScreen used to open its
// own FlameSocketService (gated on ApiClient().accessToken, which is null in
// any test/unit context that hasn't gone through real login) instead of
// borrowing the app-level RealtimeConnection. That meant an open ChatScreen
// never reacted to a push delivered on the shared connection, and — had it
// instead assigned the shared socket's single-assignment callback fields
// directly — it would have stolen every push from the conversation list.
//
// This test builds the shared connection with an injected fake socket,
// subscribes a "list-level" listener the way main_shell does, then mounts
// ChatScreen through the real realtimeConnectionProvider. It requires no
// live ApiClient and touches no network: chatServiceProvider, UserService
// and ConversationsNotifier are all faked/seeded.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/chat_provider.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/screens/chat/chat_screen.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/services/flame_socket_service.dart';
import 'package:flame/services/user_service.dart';

class _FakeSocket extends FlameSocketService {
  _FakeSocket(String token) : super(token: token);
  @override
  void connect() {}
  @override
  void dispose() {}
  @override
  bool get isConnected => true;
}

// getMessages is the only chatService method ChatScreen calls on init;
// failing it immediately keeps _messages empty without touching a network.
class _FakeChatService extends ChatService {
  @override
  Future<ServiceResult<MessagesResult>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) async {
    return ServiceResult.failure('no network in tests');
  }
}

// Never called (UserService.getCurrentUser is only invoked by loadUser,
// which this test never triggers) — exists only so CurrentUserNotifier has
// something to hold that isn't a real, network-backed UserService.
class _FakeUserService extends UserService {}

// Seeded with the conversation carrying no messages, so
// ConversationsNotifier.markAsRead (fired by _onSocketMessageNew) finds the
// conversation and short-circuits on an empty unread list instead of
// throwing "Conversation not found" against the default empty/loading state.
class _SeededConversations extends ConversationsNotifier {
  _SeededConversations(List<Conversation> initial) : super(ChatService()) {
    state = AsyncValue.data(initial);
  }
}

Conversation _conversation(String id, String otherUserId) =>
    Conversation.fromJson({
      'id': id,
      'other_user': {'id': otherUserId, 'name': 'Other'},
      'last_message_at': '2026-08-17T00:00:00.000Z',
    });

Message _msg(String id, String senderId) => Message.fromJson({
  'id': id,
  'sender_id': senderId,
  'text': 'live push',
  'type': 'text',
  'created_at': '2026-08-17T00:01:00.000Z',
});

User _me() => User.fromJson({
  'id': 'me',
  'name': 'Me',
  'age': 30,
  'bio': '',
  'interests': <dynamic>[],
  'gender': 'male',
  'photos': [],
});

void main() {
  testWidgets(
    'a push on the shared connection reaches an open ChatScreen, and the '
    'list-level listener still receives it too',
    (tester) async {
      late _FakeSocket socket;
      final conn = RealtimeConnection(createSocket: (t) {
        socket = _FakeSocket(t);
        return socket;
      });
      addTearDown(conn.dispose);
      conn.start('token-a');

      // Mimics the conversation list: already subscribed before this screen
      // ever opens, exactly the arrangement main_shell sets up.
      final listSeen = <String>[];
      conn.messageNew.listen((e) => listSeen.add(e.message.id));

      final conversation = _conversation('c1', 'u1');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatServiceProvider.overrideWithValue(_FakeChatService()),
            currentUserProvider.overrideWith(
              (ref) => CurrentUserNotifier(_FakeUserService())..setUser(_me()),
            ),
            conversationsProvider.overrideWith(
              (ref) => _SeededConversations([conversation]),
            ),
            realtimeConnectionProvider.overrideWithValue(conn),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: kSupportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: ChatScreen(conversation: conversation),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('live push'), findsNothing);

      socket.onMessageNew!(_msg('m1', 'u1'), 'c1');
      await tester.pump();
      await tester.pump();

      expect(
        find.text('live push'),
        findsOneWidget,
        reason:
            'ChatScreen must receive pushes through the shared connection, '
            'not by opening a socket of its own gated on a live ApiClient token',
      );
      expect(
        listSeen,
        ['m1'],
        reason: 'the list-level listener must still see the push too',
      );
    },
  );
}
