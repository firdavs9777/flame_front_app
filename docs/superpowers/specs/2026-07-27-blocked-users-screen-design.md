# Blocked Users Management (Sub-project D) — Design Spec

> Date: 2026-07-27 · Frontend only (`~/Desktop/Flame/flame_front_app`). Backend endpoints already exist.

## 1. Goal

Give users a **Blocked Users** screen in Settings: see who they've blocked and unblock them. This
completes the report/block safety feature (report + block shipped in Phase 4a; the "manage blocks"
half was deferred) and is a common App-Store expectation for UGC/dating apps.

## 2. Why just this (scope note)

Sub-project D was "settings enhancements": blocked-users, notification preferences, privacy/account
controls. Only **blocked-users** is fully backed today:
- `ReportService.getBlockedUsers()` (`GET /blocks`) and `unblockUser(userId)` (`DELETE /blocks/:id`)
  already exist and are real.
- **Notification preferences** are meaningless without the flame push backend → they move into
  sub-project **B (push/FCM)**.
- **Privacy/account toggles** (Discovery/Show-Distance/Show-Online) persist locally; server sync needs
  the unconfirmed `PATCH /users/me/preferences` endpoint → deferred until that's confirmed.

So D = the Blocked Users screen.

## 3. Design

- **Provider:** `blockedUsersProvider` — an `AsyncNotifier`/`FutureProvider`-style state exposing
  `AsyncValue<List<BlockedUser>>` backed by `ReportService.getBlockedUsers()`, with an `unblock(userId)`
  method that calls `ReportService.unblockUser(userId)` and, on success, removes that user from the
  list (optimistic + reconcile). `BlockedUser {id, name, blockedAt}` already exists in report_service.dart.
  Provide `reportServiceProvider` (already added in Phase 4a) to the notifier.
- **Screen:** `lib/screens/settings/blocked_users_screen.dart` — an `AppBar('Blocked Users')` + a list:
  loading spinner, error state with retry, empty state ("You haven't blocked anyone"), and rows showing
  name + a trailing "Unblock" button. Unblock → confirm dialog → `unblock(userId)` → row disappears +
  a SnackBar. Use the kit widgets + existing patterns (AppLoading, etc.).
- **Settings entry:** add a "Blocked Users" `_buildListTile` in `settings_screen.dart` (Account or a
  Privacy/Safety section) that navigates to the screen.
- **Context-safety:** capture messenger before awaits; `if (!context.mounted) return;` after the async
  gap (the pattern established this session).

## 4. Units

- `blocked_users_provider.dart` — state + unblock logic (unit-testable with a fake ReportService, like
  the report/photo providers).
- `blocked_users_screen.dart` — the UI (widget-testable with an overridden provider).
- one line in `settings_screen.dart` — the nav entry.

## 5. Testing

- Provider: load (maps getBlockedUsers → list), unblock success (removes the user + calls the service),
  unblock failure (keeps the user), with a fake ReportService (subclass override, like the Phase-3/4a
  provider tests).
- Screen: a widget test with the provider overridden to a fixed list — asserts rows render, empty state
  shows when empty, and tapping Unblock (through the confirm) calls the provider. (If widget-testing the
  full screen is heavy, at minimum test the provider + verify the screen via analyze + review.)

## 6. Out of scope

Notification preferences (→ B), privacy/account server-sync (needs the preferences endpoint), a
"blocked count" badge. The block *action* itself already exists (Phase 4a ReportBlockMenu).
