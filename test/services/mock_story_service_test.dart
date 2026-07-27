import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flame/services/story_service.dart';

const _me = StoryUserRef(userId: 'me', name: 'Me', avatarUrl: '');

void main() {
  group('MockStoryService feed', () {
    test('returns only matched users that have active stories', () async {
      final service = MockStoryService();
      final refs = List.generate(
        20,
        (i) => StoryUserRef(userId: 'user_$i', name: 'U$i', avatarUrl: ''),
      );

      final feed = await service.feed(refs);

      expect(feed, isNotEmpty);
      expect(feed.every((u) => u.hasStories), isTrue);
      expect(feed.length, lessThanOrEqualTo(refs.length));
    });

    test('markViewed flips hasViewed on the next fetch', () async {
      final service = MockStoryService();
      final refs = List.generate(
        20,
        (i) => StoryUserRef(userId: 'user_$i', name: 'U$i', avatarUrl: ''),
      );
      final feed = await service.feed(refs);
      final target = feed.first;
      final storyId = target.activeStories.first.id;

      await service.markViewed(storyId);

      final feed2 = await service.feed(refs);
      final target2 = feed2.firstWhere((u) => u.userId == target.userId);
      final story = target2.activeStories.firstWhere((s) => s.id == storyId);
      expect(story.hasViewed, isTrue);
    });
  });

  group('MockStoryService own stories', () {
    test('create adds an active story visible in myStories', () async {
      final service = MockStoryService();
      expect(await service.myStories(_me), isNull);

      final story = await service.create(
        author: _me,
        image: File('/tmp/x.jpg'),
        caption: 'hi',
      );

      expect(story.isActive, isTrue);
      final mine = await service.myStories(_me);
      expect(mine, isNotNull);
      expect(mine!.activeStories.length, 1);
      expect(mine.activeStories.first.caption, 'hi');
      expect(mine.hasUnviewed, isTrue);
    });

    test('markViewed marks own story seen', () async {
      final service = MockStoryService();
      final story =
          await service.create(author: _me, image: File('/tmp/x.jpg'));

      await service.markViewed(story.id);

      final mine = await service.myStories(_me);
      expect(mine!.hasUnviewed, isFalse);
    });

    test('delete removes an own story', () async {
      final service = MockStoryService();
      final story =
          await service.create(author: _me, image: File('/tmp/x.jpg'));

      await service.delete(story.id);

      expect(await service.myStories(_me), isNull);
    });
  });
}
