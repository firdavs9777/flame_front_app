import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/chat/widgets/matches_empty_state.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/screens/chat/chat_screen.dart';
import 'package:flame/screens/chat/chat_search_screen.dart';
import 'package:flame/screens/stories/widgets/story_tray.dart';
import 'package:flame/widgets/smart_image.dart';

class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({super.key});

  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        ref.read(matchesProvider.notifier).loadMatches(refresh: true);
        ref.read(conversationsProvider.notifier).loadConversations(refresh: true);
      }
    });
  }

  /// Opens search, unwrapping ServiceResult into the screen's contract:
  /// results on success, a throw on failure so its error branch renders.
  void _openSearch(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatSearchScreen(
          search: (query, {int limit = 20, int offset = 0}) async {
            final result = await ref.read(chatServiceProvider).searchMessages(
                  query: query, limit: limit, offset: offset,
                );
            if (!result.success) throw Exception(result.error ?? 'Search failed');
            return result.data ?? [];
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matchesState = ref.watch(matchesProvider);
    final conversationsState = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search messages',
            onPressed: () => _openSearch(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            ref.read(matchesProvider.notifier).loadMatches(refresh: true),
            ref.read(conversationsProvider.notifier).loadConversations(refresh: true),
          ]);
        },
        child: CustomScrollView(
          slivers: [
            // Stories tray (own + matches' ephemeral stories)
            const SliverToBoxAdapter(child: StoryTray()),

            // New matches section
            matchesState.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, stack) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error loading matches: $error'),
                ),
              ),
              data: (matches) {
                if (matches.isEmpty) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                return SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'New Matches',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 110,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: matches.length,
                          itemBuilder: (context, index) {
                            return _MatchCircle(match: matches[index]);
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Conversations section
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Messages',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            conversationsState.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stack) => SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('Failed to load messages', style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          ref.read(conversationsProvider.notifier).loadConversations(refresh: true);
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (conversations) {
                if (conversations.isEmpty) {
                  return const SliverFillRemaining(
                    // hasScrollBody: false lets the sliver size to its
                    // content instead of forcing it into whatever the
                    // matches strip left over, which overflowed by 13px.
                    hasScrollBody: false,
                    child: MatchesEmptyState(),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return _ConversationTile(conversation: conversations[index]);
                    },
                    childCount: conversations.length,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Finds the conversation a match's chat should open against, refreshing the
/// conversation cache once if the first look-up misses.
///
/// The miss is the NORMAL case for a brand-new match: `main_shell.dart` holds
/// every tab in an `IndexedStack` and loads conversations once at startup,
/// `MatchesScreen` refreshes once behind an `_initialized` guard, and
/// `swipe_provider.addMatch` adds the match without touching
/// `conversationsProvider`. The cached list therefore predates the match.
///
/// This used to fabricate a `Conversation` with `id: match.id` on a miss, which
/// is a MATCH id, not a conversation id — `ChatScreen` then called
/// `/conversations/<matchId>/messages` and every load and send 404'd. Returning
/// null so the caller can decline to navigate is strictly better than opening a
/// chat that cannot work.
///
/// Kept as a free function, separate from the widget, so the refresh-then-retry
/// rule is testable without a network or a rendered tree.
Future<Conversation?> resolveMatchConversation({
  required String otherUserId,
  required List<Conversation> Function() readConversations,
  required Future<void> Function() refreshConversations,
}) async {
  Conversation? lookup() =>
      readConversations().where((c) => c.otherUser.id == otherUserId).firstOrNull;

  final cached = lookup();
  if (cached != null) return cached;

  await refreshConversations();
  return lookup();
}

class _MatchCircle extends ConsumerWidget {
  final Match match;

  const _MatchCircle({required this.match});

  Future<void> _openChat(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final conversation = await resolveMatchConversation(
      otherUserId: match.user.id,
      readConversations: () => ref.read(conversationsProvider).valueOrNull ?? [],
      refreshConversations: () =>
          ref.read(conversationsProvider.notifier).loadConversations(refresh: true),
    );

    if (!context.mounted) return;

    if (conversation == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not open this chat. Please try again.')),
      );
      return;
    }

    navigator.push(
      MaterialPageRoute(builder: (_) => ChatScreen(conversation: conversation)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _openChat(context, ref),
      onLongPress: () => _confirmUnmatch(context, ref),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: match.isNew
                        ? LinearGradient(
                            colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
                          )
                        : null,
                    border: match.isNew
                        ? null
                        : Border.all(color: Colors.grey[300]!, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 32,
                    backgroundImage: match.user.primaryPhoto.toImageProvider(),
                  ),
                ),
                if (match.user.isOnline)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppTheme.successColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              match.user.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmUnmatch(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unmatch?'),
        content: Text(
          'You will no longer be matched with ${match.user.name} and this cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Unmatch',
              style: TextStyle(color: AppTheme.errorColor),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    final ok = await ref.read(matchesProvider.notifier).unmatch(match.id);
    if (!context.mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Unmatched with ${match.user.name}' : 'Could not unmatch. Please try again.',
        ),
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  final Conversation conversation;

  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      onTap: () async {
        await ref.read(conversationsProvider.notifier).markAsRead(conversation.id);
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(conversation: conversation),
            ),
          );
        }
      },
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: conversation.otherUser.primaryPhoto.toImageProvider(),
          ),
          if (conversation.otherUser.isOnline)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: AppTheme.successColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        conversation.otherUser.name,
        style: TextStyle(
          fontWeight: conversation.hasUnread ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        conversation.lastMessagePreview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: conversation.hasUnread ? Colors.black87 : Colors.grey[600],
          fontWeight: conversation.hasUnread ? FontWeight.w500 : FontWeight.normal,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            conversation.lastMessage?.timeText ?? '',
            style: TextStyle(
              fontSize: 12,
              color: conversation.hasUnread
                  ? AppTheme.primaryColor
                  : Colors.grey[500],
            ),
          ),
          if (conversation.hasUnread) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
              ),
              child: Text(
                conversation.unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
