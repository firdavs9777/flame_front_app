import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/story.dart';
import 'package:flame/providers/story_provider.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/smart_image.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/screens/stories/widgets/story_gradient_ring.dart';
import 'package:flame/screens/stories/story_viewer_screen.dart';
import 'package:flame/screens/stories/create_story_screen.dart';

/// The ring row of stories at the top of the Matches/Chat screen. Own story
/// first (with a `+` to add), then matched users' stories (coral ring when
/// unseen, grey when seen).
class StoryTray extends ConsumerWidget {
  const StoryTray({super.key});

  void _openViewer(BuildContext context, List<UserStories> users, int index) {
    if (users.isEmpty || index < 0 || index >= users.length) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StoryViewerScreen(users: users, initialUserIndex: index),
    ));
  }

  void _openCreate(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const CreateStoryScreen(),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(storiesFeedProvider).valueOrNull ?? const StoriesFeed();
    final me = ref.watch(currentUserProvider).valueOrNull;

    final others = feed.others;
    final ownHasStories = feed.own?.hasStories ?? false;
    final viewerUsers = <UserStories>[
      if (ownHasStories) feed.own!,
      ...others,
    ];

    return SizedBox(
      height: 116,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        children: [
          _OwnItem(
            avatarUrl: me?.primaryPhoto ?? feed.own?.avatarUrl ?? '',
            label: context.l10n.storyYourStory,
            hasStories: ownHasStories,
            onTapAvatar: () => ownHasStories
                ? _openViewer(context, viewerUsers, 0)
                : _openCreate(context),
            onTapAdd: () => _openCreate(context),
          ),
          for (var i = 0; i < others.length; i++)
            _UserItem(
              user: others[i],
              onTap: () => _openViewer(
                context,
                viewerUsers,
                (ownHasStories ? 1 : 0) + i,
              ),
            ),
        ],
      ),
    );
  }
}

ImageProvider? _providerFor(String url) =>
    url.isEmpty ? null : url.toImageProvider();

class _OwnItem extends StatelessWidget {
  const _OwnItem({
    required this.avatarUrl,
    required this.label,
    required this.hasStories,
    required this.onTapAvatar,
    required this.onTapAdd,
  });

  final String avatarUrl;
  final String label;
  final bool hasStories;
  final VoidCallback onTapAvatar;
  final VoidCallback onTapAdd;

  @override
  Widget build(BuildContext context) {
    final provider = _providerFor(avatarUrl);
    return SizedBox(
      width: 74,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: onTapAvatar,
                child: StoryGradientRing(
                  active: hasStories,
                  dimmed: !hasStories,
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: provider,
                    child: provider == null
                        ? const Icon(Icons.person, color: Colors.grey)
                        : null,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: onTapAdd,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      shape: BoxShape.circle,
                    ),
                    child: const CircleAvatar(
                      radius: 9,
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.add, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _UserItem extends StatelessWidget {
  const _UserItem({required this.user, required this.onTap});

  final UserStories user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final provider = _providerFor(user.avatarUrl);
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 74,
        child: Column(
          children: [
            StoryGradientRing(
              active: user.hasUnviewed,
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: provider,
                child: provider == null
                    ? const Icon(Icons.person, color: Colors.grey)
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
