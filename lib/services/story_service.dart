import 'dart:io';

import 'package:flame/models/story.dart';

/// Lightweight, denormalized reference to a story author (avoids coupling the
/// service layer to [User]/[Match]).
class StoryUserRef {
  final String userId;
  final String name;
  final String avatarUrl;

  const StoryUserRef({
    required this.userId,
    required this.name,
    required this.avatarUrl,
  });
}

/// The Stories backend seam. Swap [MockStoryService] for a real
/// `ApiStoryService` (same interface, hitting `/stories/*`) when the backend
/// ships — no UI changes required.
abstract class StoryService {
  /// Active stories from the given matched users, grouped per user. Users with
  /// no active stories are omitted.
  Future<List<UserStories>> feed(List<StoryUserRef> matches);

  /// The current user's own active stories (null if none).
  Future<UserStories?> myStories(StoryUserRef me);

  /// Upload a photo story; it expires 24h from now.
  Future<Story> create({
    required StoryUserRef author,
    required File image,
    String? caption,
  });

  Future<void> markViewed(String storyId);

  Future<void> delete(String storyId);
}

/// In-memory implementation for the frontend-first slice. Seeds deterministic
/// stories for matched users, and keeps own created stories + a viewed set for
/// the session. Not persisted — created stories vanish on restart (by design).
class MockStoryService implements StoryService {
  final List<Story> _ownStories = [];
  final Set<String> _viewed = {};
  int _createCounter = 0;

  @override
  Future<List<UserStories>> feed(List<StoryUserRef> matches) async {
    final result = <UserStories>[];
    for (final ref in matches) {
      final stories = _seedStoriesFor(ref);
      final wrapped = UserStories(
        userId: ref.userId,
        name: ref.name,
        avatarUrl: ref.avatarUrl,
        stories: stories,
      );
      if (wrapped.hasStories) result.add(wrapped);
    }
    // Unviewed first, then most recent.
    result.sort((a, b) {
      if (a.hasUnviewed != b.hasUnviewed) return a.hasUnviewed ? -1 : 1;
      final at = a.latestAt ?? a.stories.first.createdAt;
      final bt = b.latestAt ?? b.stories.first.createdAt;
      return bt.compareTo(at);
    });
    return result;
  }

  @override
  Future<UserStories?> myStories(StoryUserRef me) async {
    final active = _ownStories
        .map((s) => s.copyWith(hasViewed: _viewed.contains(s.id)))
        .where((s) => s.isActive)
        .toList();
    if (active.isEmpty) return null;
    return UserStories(
      userId: me.userId,
      name: me.name,
      avatarUrl: me.avatarUrl,
      stories: active,
    );
  }

  @override
  Future<Story> create({
    required StoryUserRef author,
    required File image,
    String? caption,
  }) async {
    final now = DateTime.now();
    final story = Story(
      id: 'own_${_createCounter++}_${now.microsecondsSinceEpoch}',
      userId: author.userId,
      mediaUrl: image.path,
      caption: caption,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
    );
    _ownStories.add(story);
    return story;
  }

  @override
  Future<void> markViewed(String storyId) async {
    _viewed.add(storyId);
  }

  @override
  Future<void> delete(String storyId) async {
    _ownStories.removeWhere((s) => s.id == storyId);
  }

  /// Deterministic seed stories for a matched user: ~2/3 of matches have 1-2
  /// stories, using seeded picsum photos so the viewer shows real images.
  List<Story> _seedStoriesFor(StoryUserRef ref) {
    final seed = ref.userId.hashCode & 0x7fffffff;
    if (seed % 3 == 0) return const []; // this user has no active stories
    final count = (seed % 2) + 1; // 1 or 2
    final now = DateTime.now();
    return List.generate(count, (i) {
      final id = '${ref.userId}_s$i';
      final createdAt = now.subtract(Duration(hours: 1 + (seed % 20) + i * 2));
      return Story(
        id: id,
        userId: ref.userId,
        mediaUrl: 'https://picsum.photos/seed/${ref.userId}_$i/900/1600',
        createdAt: createdAt,
        expiresAt: createdAt.add(const Duration(hours: 24)),
        viewCount: seed % 25,
        hasViewed: _viewed.contains(id),
      );
    }).where((s) => s.isActive).toList();
  }
}
