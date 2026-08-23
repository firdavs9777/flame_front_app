import 'dart:io';

import 'package:flame/models/story.dart';
import 'package:flame/services/api_client.dart';

/// The Stories backend seam.
///
/// Nothing here takes the viewer or the author as an argument: the bearer token
/// identifies the caller, and the SERVER decides whose stories are visible
/// (matches only — see `flame/services/storyService.js`). An earlier in-memory
/// implementation took a list of matched users because it had to fabricate the
/// feed itself; passing that list to a real backend would have been a client
/// asking to be told what it is allowed to see.
abstract class StoryService {
  /// Active stories from users the viewer is matched with, grouped per author.
  /// Authors with nothing live are omitted.
  Future<List<UserStories>> feed();

  /// The viewer's own active stories (null if none).
  Future<UserStories?> myStories();

  /// Upload a photo story; it expires 24h from now.
  Future<Story> create({required File image, String? caption});

  Future<void> markViewed(String storyId);

  Future<void> delete(String storyId);
}

/// Talks to `/stories/*`.
///
/// Reads degrade to empty rather than throwing: the tray is one strip inside
/// the Messages tab, so a story request that fails should cost the strip, not
/// the screen it sits on. Writes the user initiated ([create]) do throw, because
/// silently discarding a photo someone just posted is worse than an error.
class ApiStoryService implements StoryService {
  ApiStoryService({ApiClient? client}) : _api = client ?? ApiClient();

  final ApiClient _api;

  @override
  Future<List<UserStories>> feed() async {
    final response = await _api.get('/stories/feed');
    if (!response.success) return const [];

    final raw = response.data is Map ? response.data['users'] : null;
    if (raw is! List) return const [];

    final groups = raw
        .whereType<Map>()
        .map((u) => UserStories.fromJson(Map<String, dynamic>.from(u)))
        .where((u) => u.hasStories)
        .toList();

    // Unviewed first, then most recent — the tray reads left to right and the
    // rings people care about belong at the start.
    groups.sort((a, b) {
      if (a.hasUnviewed != b.hasUnviewed) return a.hasUnviewed ? -1 : 1;
      final at = a.latestAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.latestAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return groups;
  }

  @override
  Future<UserStories?> myStories() async {
    final response = await _api.get('/stories/my');
    if (!response.success) return null;

    final data = response.data;
    if (data is! Map) return null;
    // `ApiClient._handleResponse` unwraps with `data?['data'] ?? data`, so a
    // null `data` field falls back to the whole envelope. "No active stories"
    // therefore arrives as {success: true, data: null} rather than as null.
    if (data.containsKey('data') && data['data'] == null) return null;

    final group = UserStories.fromJson(Map<String, dynamic>.from(data));
    return group.hasStories ? group : null;
  }

  @override
  Future<Story> create({required File image, String? caption}) async {
    final response = await _api.uploadFile(
      '/stories',
      image,
      fieldName: 'media',
      fields: (caption != null && caption.trim().isNotEmpty)
          ? {'caption': caption.trim()}
          : null,
    );

    if (!response.success || response.data is! Map) {
      throw StoryException(response.error ?? 'Could not post your story');
    }
    return Story.fromJson(Map<String, dynamic>.from(response.data));
  }

  @override
  Future<void> markViewed(String storyId) async {
    // Fire-and-forget by design: this runs as the viewer turns a page, and a
    // failure only costs an unread ring that corrects itself on the next feed.
    await _api.post('/stories/$storyId/view');
  }

  @override
  Future<void> delete(String storyId) async {
    final response = await _api.delete('/stories/$storyId');
    if (!response.success) {
      throw StoryException(response.error ?? 'Could not delete that story');
    }
  }
}

/// Raised for story writes the user initiated, so the UI can say what failed.
class StoryException implements Exception {
  const StoryException(this.message);
  final String message;

  @override
  String toString() => message;
}
