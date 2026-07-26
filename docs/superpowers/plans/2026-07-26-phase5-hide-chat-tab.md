# Phase 5 — Hide the Chat Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the non-functional **Chat** tab from the main navigation so the Honest-MVP build never shows a messaging surface that can't work (empty stubs, no send endpoint, no realtime). Chat becomes unreachable; tap-to-translate (which lives inside the chat message bubble) is unreachable as a consequence.

**Architecture:** A single, surgical edit to `lib/screens/main_shell.dart` — the only place the chat screen is mounted. The bottom nav goes from 4 tabs (Discover, Chat, Profile, Settings) to 3 (Discover, Profile, Settings), and the chat-derived badge/notification plumbing and the matches/conversations preload are dropped. No chat code is deleted — it stays in the tree, just unreachable, so it's trivial to re-enable when a real messaging backend ships.

**Tech Stack:** Flutter, Dart, Riverpod, `flutter_test`.

## Global Constraints

- Do NOT edit `lib/screens/chat/matches_screen.dart` or `lib/providers/chat_provider.dart` (dirty working tree) or `lib/providers/providers.dart` (dirty). This plan touches ONLY `main_shell.dart`, which is clean.
- Do NOT delete any chat / realtime / mock files — that dead-code cleanup (spec §5-Q) is DEFERRED (see below).
- `main_shell.dart` still needs the `providers.dart` import for `currentUserProvider`; keep it.
- Commands: `flutter test`, `flutter analyze <path>`.

**Verified facts:**
- The chat screen's only mount point is `main_shell.dart:27` (`const MatchesScreen()`) — grep confirms no other `MatchesScreen(`/`ChatScreen(` entry outside `lib/screens/chat/`.
- The app smoke test (`test/widget_test.dart`) stops at splash/welcome (unauthenticated) and never reaches `MainShell`, so it is unaffected.
- Nav labels are l10n: `navDiscover`="Discover", `navChat`="Chat", `navProfile`="Profile", `navSettings`="Settings".

**Deferred (spec §5-Q — dead-code deletion, NOT in this plan):** `chat_v2_screen.dart` and the `lib/realtime/*` socket.io stack are largely dead, BUT the *live* `chat_screen.dart` imports `realtime/widgets/connection_banner.dart`, and `runtime_config_service` would be orphaned only after `lib/realtime` goes — plus `test/realtime/*` and `test/services/runtime_config_test.dart` depend on them. Deleting this subtree safely needs a careful staged removal with zero user impact; best done as its own cleanup after the dirty chat files are committed. Also deferred: removing the now-unused `MockDataService`.

---

### Task 1: Remove the Chat tab from MainShell

**Files:**
- Modify: `lib/screens/main_shell.dart`

**Interfaces:** none exported. Nav tab order becomes: Discover (0), Profile (1), Settings (2).

- [ ] **Step 1: Edit the screen list and imports**

In `lib/screens/main_shell.dart`:

1. Remove the import `import 'chat/matches_screen.dart';` (line 8).
2. In `_screens` (lines 25-30), remove the `const MatchesScreen(),` entry so the list is:

```dart
  late final List<Widget> _screens = [
    const HomeScreen(),
    const MyProfileScreen(),
    const SettingsScreen(),
  ];
```

- [ ] **Step 2: Drop the chat preload**

In `_initializeData` (lines 43-50), remove the two chat preload calls (the `matchesProvider` and
`conversationsProvider` reads), leaving only the user load:

```dart
  Future<void> _initializeData() async {
    // Load user profile.
    await ref.read(currentUserProvider.notifier).loadUser();
  }
```

- [ ] **Step 3: Drop the chat badge in build()**

In `build` (lines 52-71), remove the three notification lines (`unreadMessages`, `newMatches`,
`totalNotifications`) and the `chatBadgeCount:` argument, so the nav bar is constructed as:

```dart
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
```

- [ ] **Step 4: Update `_FlameNavBar`**

1. Remove the `chatBadgeCount` field and its constructor parameter, so the constructor is:

```dart
  const _FlameNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
```

2. In the `Row` `children`, delete the Chat `_NavItem` (the one with `Icons.chat_bubble*` /
   `context.l10n.navChat` / `badgeCount: chatBadgeCount`, lines 114-121) and renumber the remaining
   `onTap` indices so the three items are:

```dart
              _NavItem(
                selected: currentIndex == 0,
                icon: Icons.local_fire_department_outlined,
                activeIcon: Icons.local_fire_department,
                label: context.l10n.navDiscover,
                onTap: () => onTap(0),
              ),
              _NavItem(
                selected: currentIndex == 1,
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: context.l10n.navProfile,
                onTap: () => onTap(1),
              ),
              _NavItem(
                selected: currentIndex == 2,
                icon: Icons.settings_outlined,
                activeIcon: Icons.settings,
                label: context.l10n.navSettings,
                onTap: () => onTap(2),
              ),
```

Leave the private `_NavItem` widget unchanged (its optional `badgeCount` param defaults to 0 and is
simply no longer passed — harmless, and avoids extra churn).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/screens/main_shell.dart`
Expected: No issues. In particular, no "unused import" (the `matches_screen.dart` import is gone;
`providers.dart` is still used by `currentUserProvider`) and no reference to the removed
`chatBadgeCount` / notification providers remains.

> No new unit test is added for this task. An isolated `MainShell` widget test would build all three
> tab screens inside the `IndexedStack` and trigger their network-backed `initState` loads (user,
> discovery), making it flaky and heavy for what is a mechanical nav-item removal. The change is
> covered by `flutter analyze`, the full suite staying green (Task 2), and code review. The app smoke
> test does not reach `MainShell` (unauthenticated), so nothing existing regresses.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/main_shell.dart
git commit -m "feat(nav): remove the non-functional Chat tab for MVP

Chat has no real backend (empty matches/conversations stubs, no send
endpoint, no realtime), so the bottom nav drops from 4 tabs to 3 (Discover,
Profile, Settings). Chat/translate code is left in place but unreachable,
ready to re-enable when a messaging backend ships. Drops the chat badge and
the matches/conversations preload."
```

---

### Task 2: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Full test suite**

Run: `flutter test`
Expected: PASS — no existing test depends on a 4th (Chat) tab.

- [ ] **Step 2: Analyze the project**

Run: `flutter analyze`
Expected: No NEW issues attributable to `main_shell.dart`. Pre-existing unrelated lints acceptable.

- [ ] **Step 3: Commit any fixups**

```bash
git add lib/screens/main_shell.dart && git commit -m "fixup: phase-5 nav"
```

(Skip if nothing needed. Stage ONLY `main_shell.dart`.)

---

## Self-Review

**Spec coverage (Phase 5):** P (hide chat + translate) → Task 1 removes the tab, making chat AND
the in-chat translate UI unreachable. ✅ Q (delete dead code) → explicitly DEFERRED with a concrete
reason (live `connection_banner` dependency + orphaned `runtime_config` + `test/realtime`), recorded
above. ✅ (deferred by design)

**Placeholder scan:** No TBD/TODO; every step is concrete with the exact resulting code. ✅

**Consistency:** Tab indices are contiguous 0/1/2 after removal (Discover/Profile/Settings), matching
`_screens` order and `IndexedStack`. `chatBadgeCount` is removed from both the call site (Step 3) and
the `_FlameNavBar` constructor (Step 4) together — no dangling reference. `providers.dart` import is
retained for `currentUserProvider`. ✅
