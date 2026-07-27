import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/story.dart';
import 'package:flame/services/story_service.dart';
import 'package:flame/providers/match_provider.dart';
import 'package:flame/providers/user_provider.dart';

/// The active Stories service. `MockStoryService` for now; swap to a real
/// `ApiStoryService` (same interface) when the backend ships.
final storyServiceProvider = Provider<StoryService>((ref) => MockStoryService());

/// The stories tray/feed: the current user's own stories plus each matched
/// user's active stories.
class StoriesFeed {
  final UserStories? own;
  final List<UserStories> others;

  const StoriesFeed({this.own, this.others = const []});

  bool get isEmpty => own == null && others.isEmpty;
}

final storiesFeedProvider = FutureProvider<StoriesFeed>((ref) async {
  final service = ref.watch(storyServiceProvider);
  final matches = ref.watch(matchesProvider).valueOrNull ?? [];
  final me = ref.watch(currentUserProvider).valueOrNull;

  final refs = matches
      .map((m) => StoryUserRef(
            userId: m.user.id,
            name: m.user.name,
            avatarUrl: m.user.primaryPhoto,
          ))
      .toList();

  final others = await service.feed(refs);

  UserStories? own;
  if (me != null) {
    own = await service.myStories(StoryUserRef(
      userId: me.id,
      name: me.name,
      avatarUrl: me.primaryPhoto,
    ));
  }

  return StoriesFeed(own: own, others: others);
});

/// Actions that mutate story state and refresh the feed. Kept as a thin
/// controller so widgets don't reach into the service + invalidate by hand.
class StoryActions {
  StoryActions(this._ref);
  final Ref _ref;

  StoryService get _service => _ref.read(storyServiceProvider);

  Future<void> markViewed(String storyId) async {
    await _service.markViewed(storyId);
    _ref.invalidate(storiesFeedProvider);
  }

  Future<Story?> create({required File image, String? caption}) async {
    final me = _ref.read(currentUserProvider).valueOrNull;
    if (me == null) return null;
    final story = await _service.create(
      author: StoryUserRef(
        userId: me.id,
        name: me.name,
        avatarUrl: me.primaryPhoto,
      ),
      image: image,
      caption: caption,
    );
    _ref.invalidate(storiesFeedProvider);
    return story;
  }

  Future<void> delete(String storyId) async {
    await _service.delete(storyId);
    _ref.invalidate(storiesFeedProvider);
  }
}

final storyActionsProvider = Provider<StoryActions>((ref) => StoryActions(ref));
