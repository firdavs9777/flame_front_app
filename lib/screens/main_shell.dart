import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/config/env.dart';
import 'package:flame/providers/location_provider.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'chat/matches_screen.dart';
import 'discover/discover_screen.dart';
import 'profile/my_profile_screen.dart';
import 'package:flame/theme/app_tokens.dart';

final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  bool _initialized = false;

  // Create screens once to avoid GlobalKey conflicts
  late final List<Widget> _screens = [
    const DiscoverScreen(),
    if (EnvConfig.current.chatEnabled) const MatchesScreen(),
    const MyProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The durable half of the token-refresh fix: ApiClient refreshes
    // proactively without ever touching authProvider, so this is the only
    // moment at which anything learns the socket's token just went stale.
    ApiClient().onTokenRefreshed = _onTokenRefreshed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        _initializeData();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Only clear the hook if it is still ours; a later shell may own it.
    if (ApiClient().onTokenRefreshed == _onTokenRefreshed) {
      ApiClient().onTokenRefreshed = null;
    }
    super.dispose();
  }

  void _onTokenRefreshed(String token) {
    if (!mounted) return;
    if (!EnvConfig.current.chatEnabled) return;
    // `start` no-ops on an unchanged token, so this is cheap even when the
    // socket is already holding the new one.
    ref.read(realtimeConnectionProvider).start(token);
  }

  /// A resume is the other half of the same problem, from the other side.
  ///
  /// socket.io replays the token it was constructed with on every automatic
  /// reconnect, so a session backgrounded past the 15-minute access-token TTL
  /// (or moved between wifi and cellular after one) comes back to a socket
  /// retrying forever with a token the handshake middleware will never accept
  /// again. Nothing surfaces that: the Messages list simply stops updating and
  /// — since prod disables ChatScreen's REST poll — an open conversation
  /// receives nothing either. Re-syncing on resume rebuilds the socket with
  /// whatever token ApiClient holds now.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;

    // Where someone is when they come back is not where they were when they
    // left. Throttled and self-deciding, so calling it on every resume costs
    // nothing when they have not moved -- and it is what stops the deck being
    // filtered from a city the user left hours ago.
    ref.read(locationRefresherProvider).refresh();

    if (!EnvConfig.current.chatEnabled) return;
    _syncRealtime(ref.read(authProvider).status);
  }

  Future<void> _initializeData() async {
    // Load user profile.
    await ref.read(currentUserProvider.notifier).loadUser();

    if (EnvConfig.current.chatEnabled) {
      await ref.read(conversationsProvider.notifier).loadConversations(refresh: true);
      _syncRealtime(ref.read(authProvider).status);
    }
  }

  /// The socket lives as long as the signed-in session. Starting it here rather
  /// than in ChatScreen is the whole point of B1: the Messages list and the
  /// unread badge must stay live when no conversation is open.
  /// Called on every auth-state change, on resume, and once at mount, so it
  /// must be safe to call redundantly. `applySessionStatus` no-ops on an
  /// unchanged token and `listenToRealtime` no-ops on the connection it is
  /// already subscribed to — the latter matters because re-registering would
  /// move the list's subscriptions to the END of the broadcast listener order,
  /// behind an open ChatScreen's, and the badge would light up for the thread
  /// the user is actively reading.
  void _syncRealtime(AuthStatus status) {
    final conn = ref.read(realtimeConnectionProvider);
    applySessionStatus(conn, status, () => ApiClient().accessToken);
    if (conn.socket != null) {
      ref.read(conversationsProvider.notifier).listenToRealtime(conn);
    }
  }

  @override
  Widget build(BuildContext context) {
    // bottomNavIndexProvider holds a raw int that outlives a release, and this
    // list just got shorter when Settings stopped being a tab. An index written by
    // the previous version would otherwise select the wrong screen or throw inside
    // IndexedStack.
    final currentIndex =
        ref.watch(bottomNavIndexProvider).clamp(0, _screens.length - 1);
    final chatUnreadCount = ref.watch(chatUnreadCountProvider);

    // ApiClient refreshes the access token proactively, so a socket may be
    // holding a dead one; and logout must tear it down. Both arrive here as an
    // auth-state change.
    ref.listen(authProvider, (_, next) {
      if (!EnvConfig.current.chatEnabled) return;
      _syncRealtime(next.status);
    });

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _FlameNavBar(
        currentIndex: currentIndex,
        onTap: (index) =>
            ref.read(bottomNavIndexProvider.notifier).state = index,
        chatBadgeCount: chatUnreadCount,
      ),
    );
  }
}

class _FlameNavBar extends StatelessWidget {
  const _FlameNavBar({
    required this.currentIndex,
    required this.onTap,
    this.chatBadgeCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int chatBadgeCount;

  // Builds nav items in the exact order/indices of _MainShellState._screens:
  // Discover, [Chat if enabled], Profile. Settings stopped being a tab and now
  // sits behind the gear in Profile.
  List<Widget> _buildNavItems(BuildContext context) {
    var index = 0;
    final items = <Widget>[];

    final discoverIndex = index++;
    items.add(_NavItem(
      selected: currentIndex == discoverIndex,
      icon: Icons.local_fire_department_outlined,
      activeIcon: Icons.local_fire_department,
      label: context.l10n.navDiscover,
      onTap: () => onTap(discoverIndex),
    ));

    if (EnvConfig.current.chatEnabled) {
      final chatIndex = index++;
      items.add(_NavItem(
        selected: currentIndex == chatIndex,
        icon: Icons.chat_bubble_outline,
        activeIcon: Icons.chat_bubble,
        label: context.l10n.navChat,
        onTap: () => onTap(chatIndex),
        badgeCount: chatBadgeCount,
      ));
    }

    final profileIndex = index++;
    items.add(_NavItem(
      selected: currentIndex == profileIndex,
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: context.l10n.navProfile,
      onTap: () => onTap(profileIndex),
    ));


    return items;
  }

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        boxShadow: [
          BoxShadow(
            // A scrim under the bar, not a colour: it stays dark in both themes
            // because it darkens whatever is behind it.
            color: context.viewerScrim.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _buildNavItems(context),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.selected,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
  });

  final bool selected;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    // Was a brightness conditional with IDENTICAL branches — a theme check that
    // decided nothing. secondaryText resolves per theme, which is what that
    // conditional was reaching for.
    final unselectedColor = context.secondaryText;
    final color = selected ? AppColors.primary : unselectedColor;

    Widget iconWidget = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: Icon(
        selected ? activeIcon : icon,
        key: ValueKey(selected),
        color: color,
        size: 24,
      ),
    );

    if (badgeCount > 0) {
      iconWidget = AppDotBadge(count: badgeCount, child: iconWidget);
    }

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: AppRadius.borderRound,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTypography.labelSmall.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
