import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/chat_provider.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/services/websocket_service.dart';

// A ConversationsNotifier that skips real loading and starts from a fixed
// AsyncValue, so chatUnreadCountProvider can be tested against known data
// without hitting the network or a real WebSocket. Safe because
// EnvConfig.current.realtimeEnabled is false in the test environment (no
// APP_ENV=local dart-define), so the base constructor's _initWebSocket()
// no-ops before touching the WebSocketService singleton.
class _FixedConversationsNotifier extends ConversationsNotifier {
  _FixedConversationsNotifier(AsyncValue<List<Conversation>> initial)
      : super(ChatService(), WebSocketService()) {
    state = initial;
  }
}

Conversation _conversation(String id, int unreadCount) {
  return Conversation(
    id: id,
    otherUser: User.fromJson({
      'id': 'user-$id',
      'name': 'User $id',
      'age': 25,
      'bio': '',
      'interests': [],
      'gender': 'female',
      'photos': [],
    }),
    messages: const [],
    lastMessageAt: DateTime(2026, 1, 1),
    unreadCount: unreadCount,
  );
}

ProviderContainer _containerWith(AsyncValue<List<Conversation>> conversations) {
  final container = ProviderContainer(
    overrides: [
      conversationsProvider.overrideWith(
        (ref) => _FixedConversationsNotifier(conversations),
      ),
    ],
  );
  return container;
}

void main() {
  test('sums unreadCount across all loaded conversations', () {
    final container = _containerWith(AsyncValue.data([
      _conversation('1', 3),
      _conversation('2', 0),
      _conversation('3', 5),
    ]));
    addTearDown(container.dispose);

    expect(container.read(chatUnreadCountProvider), 8);
  });

  test('is 0 for an empty conversation list', () {
    final container = _containerWith(const AsyncValue.data([]));
    addTearDown(container.dispose);

    expect(container.read(chatUnreadCountProvider), 0);
  });

  test('is 0 while conversations are loading', () {
    final container = _containerWith(const AsyncValue.loading());
    addTearDown(container.dispose);

    expect(container.read(chatUnreadCountProvider), 0);
  });

  test('is 0 on an error state', () {
    final container = _containerWith(AsyncValue.error('boom', StackTrace.empty));
    addTearDown(container.dispose);

    expect(container.read(chatUnreadCountProvider), 0);
  });
}
