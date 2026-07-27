/// An ephemeral photo story. Active for 24 hours from creation.
class Story {
  final String id;
  final String userId;

  /// Photo source: a network URL, a `data:` URI, or a local file path
  /// (own just-created stories in the mock service).
  final String mediaUrl;
  final String? caption;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int viewCount;
  final bool hasViewed;

  const Story({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    this.caption,
    required this.createdAt,
    required this.expiresAt,
    this.viewCount = 0,
    this.hasViewed = false,
  });

  /// True while the story is within its 24h window.
  bool get isActive => expiresAt.isAfter(DateTime.now());

  factory Story.fromJson(Map<String, dynamic> json) {
    final created = json['created_at'] != null
        ? DateTime.parse(json['created_at'])
        : DateTime.now();
    return Story(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      mediaUrl: json['media_url'] ?? '',
      caption: json['caption'],
      createdAt: created,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'])
          : created.add(const Duration(hours: 24)),
      viewCount: json['view_count'] ?? 0,
      hasViewed: json['has_viewed'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'media_url': mediaUrl,
      'caption': caption,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'view_count': viewCount,
      'has_viewed': hasViewed,
    };
  }

  Story copyWith({
    int? viewCount,
    bool? hasViewed,
  }) {
    return Story(
      id: id,
      userId: userId,
      mediaUrl: mediaUrl,
      caption: caption,
      createdAt: createdAt,
      expiresAt: expiresAt,
      viewCount: viewCount ?? this.viewCount,
      hasViewed: hasViewed ?? this.hasViewed,
    );
  }
}

/// A user's stories, grouped for the tray and viewer. [avatarUrl] and [name]
/// are denormalized so the tray can render without a separate user lookup.
class UserStories {
  final String userId;
  final String name;
  final String avatarUrl;
  final List<Story> stories;

  const UserStories({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.stories,
  });

  /// Only the stories still within their 24h window, oldest first (viewer order).
  List<Story> get activeStories {
    final active = stories.where((s) => s.isActive).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return active;
  }

  bool get hasStories => activeStories.isNotEmpty;

  /// True when at least one active story hasn't been seen (drives the ring).
  bool get hasUnviewed => activeStories.any((s) => !s.hasViewed);

  int get unviewedCount => activeStories.where((s) => !s.hasViewed).length;

  /// Newest active story time, for ordering the tray.
  DateTime? get latestAt {
    final active = activeStories;
    if (active.isEmpty) return null;
    return active.map((s) => s.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
  }

  UserStories copyWith({List<Story>? stories}) {
    return UserStories(
      userId: userId,
      name: name,
      avatarUrl: avatarUrl,
      stories: stories ?? this.stories,
    );
  }
}
