import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/story.dart';

Story _story({
  required String id,
  required Duration age,
  Duration ttl = const Duration(hours: 24),
  bool viewed = false,
}) {
  final created = DateTime.now().subtract(age);
  return Story(
    id: id,
    userId: 'u1',
    mediaUrl: 'x',
    createdAt: created,
    expiresAt: created.add(ttl),
    hasViewed: viewed,
  );
}

void main() {
  group('Story.isActive', () {
    test('is true within the 24h window', () {
      expect(_story(id: 'a', age: const Duration(hours: 3)).isActive, isTrue);
    });

    test('is false once expired', () {
      expect(_story(id: 'a', age: const Duration(hours: 25)).isActive, isFalse);
    });
  });

  group('UserStories', () {
    test('activeStories excludes expired and sorts oldest first', () {
      final us = UserStories(
        userId: 'u1',
        name: 'Ann',
        avatarUrl: '',
        stories: [
          _story(id: 'new', age: const Duration(hours: 1)),
          _story(id: 'old', age: const Duration(hours: 5)),
          _story(id: 'expired', age: const Duration(hours: 30)),
        ],
      );
      final active = us.activeStories;
      expect(active.map((s) => s.id), ['old', 'new']);
    });

    test('hasUnviewed reflects unseen active stories only', () {
      final allSeen = UserStories(
        userId: 'u1',
        name: 'Ann',
        avatarUrl: '',
        stories: [_story(id: 'a', age: const Duration(hours: 1), viewed: true)],
      );
      expect(allSeen.hasUnviewed, isFalse);

      final oneUnseen = UserStories(
        userId: 'u1',
        name: 'Ann',
        avatarUrl: '',
        stories: [
          _story(id: 'a', age: const Duration(hours: 1), viewed: true),
          _story(id: 'b', age: const Duration(hours: 2), viewed: false),
        ],
      );
      expect(oneUnseen.hasUnviewed, isTrue);
      expect(oneUnseen.unviewedCount, 1);
    });

    test('an expired unseen story does not count as unviewed', () {
      final us = UserStories(
        userId: 'u1',
        name: 'Ann',
        avatarUrl: '',
        stories: [_story(id: 'a', age: const Duration(hours: 30), viewed: false)],
      );
      expect(us.hasStories, isFalse);
      expect(us.hasUnviewed, isFalse);
    });
  });

  group('UserStories.fromJson', () {
    test('parses a grouped author payload from the feed', () {
      final created = DateTime.now().subtract(const Duration(hours: 2));
      final group = UserStories.fromJson({
        'user_id': 'u7',
        'name': 'Mina',
        'avatar_url': 'https://cdn/x.jpg',
        'stories': [
          {
            'id': 's1',
            'user_id': 'u7',
            'media_url': 'https://cdn/s1.jpg',
            'created_at': created.toIso8601String(),
            'expires_at': created.add(const Duration(hours: 24)).toIso8601String(),
            'view_count': 4,
            'has_viewed': true,
          },
        ],
      });

      expect(group.userId, 'u7');
      expect(group.name, 'Mina');
      expect(group.avatarUrl, 'https://cdn/x.jpg');
      expect(group.stories.single.id, 's1');
      expect(group.stories.single.viewCount, 4);
      expect(group.hasUnviewed, isFalse);
    });

    test('survives an author with no stories array', () {
      // The server never sends this, but a group with a missing `stories` key
      // must not take the tray down with a cast error.
      final group = UserStories.fromJson({'user_id': 'u1', 'name': 'A'});
      expect(group.stories, isEmpty);
      expect(group.avatarUrl, '');
      expect(group.hasStories, isFalse);
    });
  });
}
