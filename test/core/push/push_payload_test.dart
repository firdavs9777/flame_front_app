import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/navigation/app_routes.dart';
import 'package:flame/core/push/push_payload.dart';

/// The payloads below are copied from the server's own builders in
/// `flame/services/pushService.js` (chatPushPayload / matchPushPayload) rather
/// than invented here. If the server changes shape, these should fail.
void main() {
  group('parsing', () {
    test('reads a chat_message payload', () {
      final payload = PushPayload.fromData({
        'type': 'chat_message',
        'conversationId': 'conv-1',
      });

      expect(payload.type, PushType.chatMessage);
      expect(payload.conversationId, 'conv-1');
      expect(payload.matchId, isNull);
    });

    test('reads a new_match payload', () {
      final payload = PushPayload.fromData({
        'type': 'new_match',
        'matchId': 'match-9',
        'conversationId': 'conv-2',
      });

      expect(payload.type, PushType.newMatch);
      expect(payload.matchId, 'match-9');
      expect(payload.conversationId, 'conv-2');
    });

    test('treats the empty string the server sends for a missing id as absent',
        () {
      // sanitizeData never omits a key: chatPushPayload writes '' when there
      // is no conversation. Without this, destination would route to a chat
      // whose id is the empty string.
      final payload = PushPayload.fromData({
        'type': 'new_match',
        'matchId': '',
        'conversationId': '',
      });

      expect(payload.matchId, isNull);
      expect(payload.conversationId, isNull);
    });

    test('an unrecognised type is unknown rather than an error', () {
      final payload = PushPayload.fromData({'type': 'super_like_received'});

      expect(payload.type, PushType.unknown);
    });

    test('survives a payload with no type and a null map', () {
      expect(PushPayload.fromData({}).type, PushType.unknown);
      expect(PushPayload.fromData(null).type, PushType.unknown);
    });
  });

  group('campaigns', () {
    test('a promotion routes to the route it names', () {
      final payload = PushPayload.fromData({
        'type': 'promotion',
        'route': AppRoutes.discoverFilters,
      });

      expect(payload.type, PushType.promotion);
      expect(payload.destination?.routeName, AppRoutes.discoverFilters);
    });

    test('a promotion naming an unknown route opens the app instead', () {
      // A campaign authored against a route a later release removed. It must
      // under-deliver, never strand the user on a not-found screen.
      final payload = PushPayload.fromData({
        'type': 'promotion',
        'route': '/screen/that/was/deleted',
      });

      expect(payload.destination, isNull);
    });

    test('a promotion cannot name a route that needs typed arguments', () {
      // AppRoutes.chat is reachable, but only with ChatRouteArgs. A payload
      // carries none, so honouring it would render RouteNotFoundScreen.
      for (final route in [
        AppRoutes.chat,
        AppRoutes.profileDetail,
        AppRoutes.mediaViewer,
        AppRoutes.storyViewer,
      ]) {
        final payload =
            PushPayload.fromData({'type': 'promotion', 'route': route});
        expect(payload.destination, isNull,
            reason: '$route needs arguments a campaign cannot supply');
      }
    });

    test('a promotion with no route at all opens the app', () {
      expect(
        PushPayload.fromData({'type': 'promotion', 'route': ''}).destination,
        isNull,
      );
    });

    test('a re-engagement push routes nowhere by design', () {
      final payload = PushPayload.fromData({'type': 'reengagement'});

      expect(payload.type, PushType.reengagement);
      expect(payload.destination, isNull);
    });
  });

  group('destination', () {
    test('a chat message opens its conversation by id', () {
      final payload = PushPayload.fromData({
        'type': 'chat_message',
        'conversationId': 'conv-1',
      });

      final destination = payload.destination;
      expect(destination, isNotNull);
      expect(destination!.routeName, AppRoutes.chat);

      final args = destination.arguments as ChatRouteArgs;
      expect(args.id, 'conv-1');
      // The id constructor, not the conversation one: a notification carries
      // an id and nothing else, and ChatRouteResolver fetches from there.
      expect(args.conversation, isNull);
    });

    test('a new match opens the conversation it created', () {
      final payload = PushPayload.fromData({
        'type': 'new_match',
        'matchId': 'match-9',
        'conversationId': 'conv-2',
      });

      expect(payload.destination?.routeName, AppRoutes.chat);
      expect((payload.destination!.arguments as ChatRouteArgs).id, 'conv-2');
    });

    test('a match with no conversation yet navigates nowhere', () {
      // Rather than guessing at a screen. The app simply opens.
      final payload = PushPayload.fromData({
        'type': 'new_match',
        'matchId': 'match-9',
        'conversationId': '',
      });

      expect(payload.destination, isNull);
    });

    test('an unknown type navigates nowhere', () {
      expect(PushPayload.fromData({'type': 'whatever'}).destination, isNull);
    });

    test('every destination it can produce is a routable name', () {
      // AppRoutes.all is what the router's own test asserts resolves. A
      // destination outside it would land on RouteNotFoundScreen.
      for (final data in [
        {'type': 'chat_message', 'conversationId': 'c'},
        {'type': 'new_match', 'conversationId': 'c', 'matchId': 'm'},
      ]) {
        final destination = PushPayload.fromData(data).destination;
        expect(AppRoutes.all, contains(destination!.routeName));
      }
    });
  });
}
