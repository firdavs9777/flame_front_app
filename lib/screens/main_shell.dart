import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'home/home_screen.dart';
import 'chat/matches_screen.dart';
import 'profile/my_profile_screen.dart';
import 'settings/settings_screen.dart';

final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _initialized = false;

  // Create screens once to avoid GlobalKey conflicts
  late final List<Widget> _screens = [
    const HomeScreen(),
    const MatchesScreen(),
    const MyProfileScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        _initializeData();
      }
    });
  }

  Future<void> _initializeData() async {
    // Load user profile first
    await ref.read(currentUserProvider.notifier).loadUser();

    // Then load other data in parallel
    ref.read(matchesProvider.notifier).loadMatches(refresh: true);
    ref.read(conversationsProvider.notifier).loadConversations(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(bottomNavIndexProvider);
    final unreadMessages = ref.watch(unreadMessagesCountProvider);
    final newMatches = ref.watch(newMatchesCountProvider);
    final totalNotifications = unreadMessages + newMatches;

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _FlameNavBar(
        currentIndex: currentIndex,
        onTap: (index) =>
            ref.read(bottomNavIndexProvider.notifier).state = index,
        chatBadgeCount: totalNotifications,
      ),
    );
  }
}

class _FlameNavBar extends StatelessWidget {
  const _FlameNavBar({
    required this.currentIndex,
    required this.onTap,
    required this.chatBadgeCount,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int chatBadgeCount;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
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
            children: [
              _NavItem(
                selected: currentIndex == 0,
                icon: Icons.local_fire_department_outlined,
                activeIcon: Icons.local_fire_department,
                label: context.l10n.navDiscover,
                onTap: () => onTap(0),
              ),
              _NavItem(
                selected: currentIndex == 1,
                icon: Icons.chat_bubble_outline,
                activeIcon: Icons.chat_bubble,
                label: context.l10n.navChat,
                badgeCount: chatBadgeCount,
                onTap: () => onTap(1),
              ),
              _NavItem(
                selected: currentIndex == 2,
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: context.l10n.navProfile,
                onTap: () => onTap(2),
              ),
              _NavItem(
                selected: currentIndex == 3,
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: context.l10n.navSettings,
                onTap: () => onTap(3),
              ),
            ],
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
    final unselectedColor =
        Theme.of(context).brightness == Brightness.dark ? AppColors.gray500 : AppColors.gray500;
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
