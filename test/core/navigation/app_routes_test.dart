import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/navigation/app_routes.dart';
import 'package:flame/models/conversation.dart';
import 'package:flame/models/user.dart';

User _user() => User.fromJson({'id': 'u1', 'name': 'Bea', 'photos': <dynamic>[]});

Conversation _conversation(String id) => Conversation(
      id: id,
      otherUser: _user(),
      lastMessageAt: DateTime(2026, 1, 1),
    );

void main() {
  group('AppRoutes.all', () {
    test('lists every route name exactly once', () {
      // The router's test iterates this list, so a name missing from it is a
      // destination nothing ever checks resolves.
      expect(AppRoutes.all.toSet().length, AppRoutes.all.length,
          reason: 'duplicate route name');
      expect(AppRoutes.all, contains(AppRoutes.chat));
      expect(AppRoutes.all, contains(AppRoutes.discoverFilters));
      expect(AppRoutes.all.length, 15);
    });

    test('keeps the one pre-existing route string unchanged', () {
      // Already shipped and pushed by name from my_profile_screen; changing it
      // would break that call site silently.
      expect(AppRoutes.discoverFilters, '/discover/filters');
    });

    test('every name is a rooted path', () {
      for (final name in AppRoutes.all) {
        expect(name.startsWith('/'), isTrue, reason: '$name must start with /');
      }
    });
  });

  group('ChatRouteArgs', () {
    test('the conversation form carries a conversation and no id', () {
      final args = ChatRouteArgs.conversation(_conversation('c1'));
      expect(args.conversation, isNotNull);
      expect(args.id, isNull);
    });

    test('the id form carries an id and no conversation', () {
      const args = ChatRouteArgs.id('c9');
      expect(args.id, 'c9');
      expect(args.conversation, isNull);
    });

    test('the list path can reach its conversation without a fetch', () {
      // Why two constructors rather than one nullable pair: the list already
      // holds the conversation and must not pay for a round trip, while a
      // notification only ever has an id. Neither can express both or neither.
      final args = ChatRouteArgs.conversation(_conversation('c1'));
      expect(args.conversation!.id, 'c1');
    });
  });

  group('argument types', () {
    test('ProfileDetailArgs defaults isPreview to false', () {
      // The default matters: the preview flag hides the like/pass buttons, so
      // losing it shows a user their own actions on their own profile.
      final args = ProfileDetailArgs(user: _user());
      expect(args.isPreview, isFalse);
    });

    test('MediaViewerArgs keeps url and heroTag distinct', () {
      const args = MediaViewerArgs(url: 'https://x/y.jpg', heroTag: 'msg-1');
      expect(args.url, 'https://x/y.jpg');
      expect(args.heroTag, 'msg-1');
    });

    test('StoryViewerArgs carries the users and the starting index', () {
      const args = StoryViewerArgs(users: [], initialUserIndex: 2);
      expect(args.users, isEmpty);
      expect(args.initialUserIndex, 2);
    });
  });
}
