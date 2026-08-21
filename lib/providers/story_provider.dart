import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/story.dart';
import 'package:flame/services/story_service.dart';

/// The active Stories service.
final storyServiceProvider = Provider<StoryService>((ref) => ApiStoryService());

/// The stories tray/feed: the current user's own stories plus each matched
/// user's active stories.
class StoriesFeed {
  final UserStories? own;
  final List<UserStories> others;

  const StoriesFeed({this.own, this.others = const []});

  bool get isEmpty => own == null && others.isEmpty;
}

/// Both halves of the tray in one request pair.
///
/// Neither call is given a user list: the server derives visibility from the
/// bearer token, so this no longer depends on `matchesProvider` or
/// `currentUserProvider` the way the fabricated version did.
final storiesFeedProvider = FutureProvider<StoriesFeed>((ref) async {
  final service = ref.watch(storyServiceProvider);

  final results = await Future.wait([
    service.feed(),
    service.myStories(),
  ]);

  return StoriesFeed(
    own: results[1] as UserStories?,
    others: results[0] as List<UserStories>,
  );
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

  /// Throws on failure rather than returning null: the caller has a photo the
  /// user chose, and needs to know whether it actually posted.
  Future<Story> create({required File image, String? caption}) async {
    final story = await _service.create(image: image, caption: caption);
    _ref.invalidate(storiesFeedProvider);
    return story;
  }

  Future<void> delete(String storyId) async {
    await _service.delete(storyId);
    _ref.invalidate(storiesFeedProvider);
  }
}

final storyActionsProvider = Provider<StoryActions>((ref) => StoryActions(ref));
