import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/config/env.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'chat/matches_screen.dart';
import 'home/home_screen.dart';
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
    if (EnvConfig.current.chatEnabled) const MatchesScreen(),
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
    // Load user profile.
    await ref.read(currentUserProvider.notifier).loadUser();

    if (EnvConfig.current.chatEnabled) {
      await ref.read(conversationsProvider.notifier).loadConversations(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(bottomNavIndexProvider);

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _FlameNavBar(
        currentIndex: currentIndex,
        onTap: (index) =>
            ref.read(bottomNavIndexProvider.notifier).state = index,
      ),
    );
  }
}

class _FlameNavBar extends StatelessWidget {
  const _FlameNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  // Builds nav items in the exact order/indices of _MainShellState._screens:
  // Discover, [Chat if enabled], Profile, Settings.
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

    final settingsIndex = index++;
    items.add(_NavItem(
      selected: currentIndex == settingsIndex,
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: context.l10n.navSettings,
      onTap: () => onTap(settingsIndex),
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
  });

  final bool selected;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unselectedColor =
        Theme.of(context).brightness == Brightness.dark ? AppColors.gray500 : AppColors.gray500;
    final color = selected ? AppColors.primary : unselectedColor;

    final iconWidget = AnimatedSwitcher(
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
