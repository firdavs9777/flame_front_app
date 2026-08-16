// Opening a chat from a new match used to 404 on every load and send.
//
// The tap handler looked the conversation up in the CACHED conversations list
// and, on a miss, fabricated `Conversation(id: match.id, matchId: match.id)` —
// a MATCH id where ChatScreen needs a CONVERSATION id. And the miss is the
// normal case: the cache is loaded once at startup and a brand-new match is not
// in it.
//
// `resolveMatchConversation` is the extracted rule: look, refresh once, look
// again, and report a miss rather than inventing an id. It takes its reads and
// its refresh as callbacks precisely so this test needs no network and no
// rendered tree.
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/chat/matches_screen.dart';

// Built through fromJson rather than the constructor so the test does not have
// to know User's required fields, and so it doubles as a check on the payload
// keys the app actually parses.
Conversation _conversation(String id, String otherUserId) =>
    Conversation.fromJson({
      'id': id,
      'other_user': {'id': otherUserId, 'name': 'Other $otherUserId'},
      'last_message_at': '2026-08-16T00:00:00.000Z',
    });

void main() {
  test('returns the cached conversation without refreshing', () async {
    var refreshes = 0;
    final cached = [_conversation('conv-1', 'user-1')];

    final found = await resolveMatchConversation(
      otherUserId: 'user-1',
      readConversations: () => cached,
      refreshConversations: () async => refreshes++,
    );

    expect(found?.id, 'conv-1');
    expect(refreshes, 0, reason: 'a cache hit must not trigger a network call');
  });

  test('refreshes once and finds a conversation the cache did not have',
      () async {
    // The state a brand-new match starts in: the cache predates the match.
    var conversations = <Conversation>[];
    var refreshes = 0;

    final found = await resolveMatchConversation(
      otherUserId: 'user-1',
      readConversations: () => conversations,
      refreshConversations: () async {
        refreshes++;
        conversations = [_conversation('conv-1', 'user-1')];
      },
    );

    expect(refreshes, 1);
    expect(found, isNotNull);
    expect(
      found!.id,
      'conv-1',
      reason: 'the id must come from the server, never from the match',
    );
  });

  test('returns null rather than fabricating a conversation when still missing',
      () async {
    var refreshes = 0;

    final found = await resolveMatchConversation(
      otherUserId: 'user-1',
      readConversations: () => const <Conversation>[],
      refreshConversations: () async => refreshes++,
    );

    expect(refreshes, 1, reason: 'it must try a refresh before giving up');
    expect(
      found,
      isNull,
      reason: 'not navigating beats navigating into a chat that 404s',
    );
  });

  test('refreshes at most once, even when the second look-up also misses',
      () async {
    var refreshes = 0;

    await resolveMatchConversation(
      otherUserId: 'user-1',
      readConversations: () => const <Conversation>[],
      refreshConversations: () async => refreshes++,
    );

    expect(refreshes, 1, reason: 'a miss must not become a refresh loop');
  });

  test('does not match a conversation with a different user', () async {
    var refreshes = 0;
    final cached = [_conversation('conv-2', 'someone-else')];

    final found = await resolveMatchConversation(
      otherUserId: 'user-1',
      readConversations: () => cached,
      refreshConversations: () async => refreshes++,
    );

    expect(found, isNull);
    expect(refreshes, 1);
  });
}
