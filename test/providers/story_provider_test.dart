import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/story.dart';
import 'package:flame/providers/story_provider.dart';
import 'package:flame/services/story_service.dart';

UserStories _group(String userId, {bool viewed = false}) {
  final created = DateTime.now().subtract(const Duration(hours: 1));
  return UserStories(
    userId: userId,
    name: userId,
    avatarUrl: '',
    stories: [
      Story(
        id: '${userId}_s1',
        userId: userId,
        mediaUrl: 'x',
        createdAt: created,
        expiresAt: created.add(const Duration(hours: 24)),
        hasViewed: viewed,
      ),
    ],
  );
}

class _FakeStoryService implements StoryService {
  _FakeStoryService({this.others = const [], this.own, this.createThrows = false});

  final List<UserStories> others;
  final UserStories? own;
  final bool createThrows;

  int feedCalls = 0;
  final List<String> viewed = [];
  final List<String> deleted = [];

  @override
  Future<List<UserStories>> feed() async {
    feedCalls++;
    return others;
  }

  @override
  Future<UserStories?> myStories() async => own;

  @override
  Future<Story> create({required File image, String? caption}) async {
    if (createThrows) throw const StoryException('upload failed');
    return _group('me').stories.first;
  }

  @override
  Future<void> markViewed(String storyId) async => viewed.add(storyId);

  @override
  Future<void> delete(String storyId) async => deleted.add(storyId);
}

ProviderContainer _containerWith(_FakeStoryService service) {
  final container = ProviderContainer(
    overrides: [storyServiceProvider.overrideWithValue(service)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('the feed provider carries both halves of the tray', () async {
    final container = _containerWith(_FakeStoryService(
      others: [_group('u1')],
      own: _group('me'),
    ));

    final feed = await container.read(storiesFeedProvider.future);

    expect(feed.own!.userId, 'me');
    expect(feed.others.single.userId, 'u1');
    expect(feed.isEmpty, isFalse);
  });

  test('an empty feed is empty rather than fabricated', () async {
    // The service this replaced seeded stories for two thirds of a user's
    // matches, so the tray was never empty and never truthful.
    final container = _containerWith(_FakeStoryService());

    final feed = await container.read(storiesFeedProvider.future);

    expect(feed.isEmpty, isTrue);
  });

  test('the feed provider asks the server rather than passing it a user list',
      () async {
    final service = _FakeStoryService(others: [_group('u1')]);
    final container = _containerWith(service);

    await container.read(storiesFeedProvider.future);

    // Nothing about matches or the current user is read to build this request:
    // visibility is the server's call, made from the bearer token.
    expect(service.feedCalls, 1);
  });

  test('create rethrows so the composer can report a failed upload', () async {
    final container = _containerWith(_FakeStoryService(createThrows: true));

    await expectLater(
      container.read(storyActionsProvider).create(image: File('x.jpg')),
      throwsA(isA<StoryException>()),
    );
  });

  test('markViewed and delete reach the service and refresh the feed', () async {
    final service = _FakeStoryService(others: [_group('u1')]);
    final container = _containerWith(service);
    await container.read(storiesFeedProvider.future);

    await container.read(storyActionsProvider).markViewed('s9');
    await container.read(storyActionsProvider).delete('s7');

    expect(service.viewed, ['s9']);
    expect(service.deleted, ['s7']);
    // Both invalidate, so the next read re-fetches rather than serving a ring
    // that is already out of date.
    await container.read(storiesFeedProvider.future);
    expect(service.feedCalls, greaterThan(1));
  });
}
