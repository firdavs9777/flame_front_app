# Phase 6a — Account Deletion (store compliance) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make in-app **account deletion** actually work. Apps that create accounts must offer in-app deletion (App Store guideline 5.1.1(v) / Play). The delete dialog and the `deleteAccount` service already exist, but the dialog's confirm button is a TODO that shows a *fake* "Account deletion requested" SnackBar without calling anything.

**Architecture:** Add a small, unit-testable `deleteAccount({password})` to `CurrentUserNotifier` (it holds the `UserService`), and wire the existing settings confirm dialog to it — on success clear the user and log out (routing to welcome), on failure surface a real error. Fix the dialog's defunct-context bug (capture the messenger from the screen context before the dialog await) — the same class of bug caught in an earlier phase.

**Tech Stack:** Flutter, Dart, Riverpod, `flutter_test`.

## Global Constraints

- `DELETE /users/me` with body `{password, reason?}` is implemented in `UserService.deleteAccount` (`user_service.dart:202`); it clears tokens on success. Do not change it.
- Touch ONLY `lib/providers/user_provider.dart` and `lib/screens/settings/settings_screen.dart` (both clean). Do not edit any dirty working-tree file.
- Context-safety: capture `ScaffoldMessenger` from the screen context BEFORE `showDialog`/await; never use a dialog context across an async gap (repo enforces `use_build_context_synchronously`).
- Commands: `flutter test <path>`, `flutter analyze <paths>`.

**Age gate (spec §6-R) — already satisfied, no work:** the registration age slider is `min: 18`
(`step_profile_info.dart:185`), so a user cannot select under 18. That is an acceptable self-attested
18+ gate. Recorded here so it isn't re-opened.

---

### Task 1: `deleteAccount` provider method

**Files:**
- Modify: `lib/providers/user_provider.dart`
- Test: `test/providers/delete_account_test.dart` (create)

**Interfaces:**
- Consumes: `UserService.deleteAccount({required String password, String? reason})`.
- Produces on `CurrentUserNotifier`: `Future<bool> deleteAccount({required String password})` —
  calls the service; on success clears the local user (`state = AsyncValue.data(null)`) and returns
  true; returns false on failure (state unchanged).

- [ ] **Step 1: Write the failing test**

Create `test/providers/delete_account_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/providers/user_provider.dart';

class _FakeUserService extends UserService {
  String? deletedPassword;
  bool succeed = true;

  @override
  Future<ServiceResult<void>> deleteAccount({
    required String password,
    String? reason,
  }) async {
    deletedPassword = password;
    return succeed
        ? ServiceResult.success(null)
        : ServiceResult.failure('Wrong password');
  }
}

User _user() => User.fromJson({
      'id': 'u1', 'name': 'Ann', 'age': 27, 'bio': '',
      'interests': <dynamic>[], 'gender': 'female', 'photos': <dynamic>[],
    });

void main() {
  test('deleteAccount success calls service with password and clears user', () async {
    final fake = _FakeUserService();
    final n = CurrentUserNotifier(fake)..setUser(_user());

    final ok = await n.deleteAccount(password: 'secret');

    expect(ok, isTrue);
    expect(fake.deletedPassword, 'secret');
    expect(n.state.value, isNull); // user cleared
  });

  test('deleteAccount failure returns false and keeps the user', () async {
    final fake = _FakeUserService()..succeed = false;
    final n = CurrentUserNotifier(fake)..setUser(_user());

    final ok = await n.deleteAccount(password: 'wrong');

    expect(ok, isFalse);
    expect(n.state.value, isNotNull); // user unchanged
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/delete_account_test.dart`
Expected: FAIL — `deleteAccount` not defined on `CurrentUserNotifier`.

- [ ] **Step 3: Implement**

In `lib/providers/user_provider.dart`, add a method to `CurrentUserNotifier` (e.g. after
`deletePhotoAt`/`setMainPhotoAt` or near `clearUser`):

```dart
  /// Deletes the account via the API. On success clears the local user; the
  /// caller is responsible for logging out / routing away. Returns false on
  /// failure (e.g. wrong password) with state unchanged.
  Future<bool> deleteAccount({required String password}) async {
    final result = await _userService.deleteAccount(password: password);
    if (result.success) {
      clearUser();
      return true;
    }
    return false;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/delete_account_test.dart`
Expected: PASS (both).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/providers/user_provider.dart`
Expected: No new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/user_provider.dart test/providers/delete_account_test.dart
git commit -m "feat(account): deleteAccount provider method

CurrentUserNotifier.deleteAccount(password) calls the existing
UserService.deleteAccount, clears the local user on success, and reports
false on failure. UI wiring follows."
```

---

### Task 2: Wire the settings delete dialog

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart` (`_showDeleteAccountDialog`, lines 345-388)

**Interfaces:**
- Consumes: `currentUserProvider.notifier.deleteAccount({password})` (Task 1);
  `authProvider.notifier.logout()` (existing, `auth_provider.dart:258`).

- [ ] **Step 1: Implement**

Replace `_showDeleteAccountDialog` (`settings_screen.dart:345-388`) so it (a) captures the messenger
from the screen context before `showDialog`, (b) renames the builder context to `dialogContext`,
and (c) calls the real delete on confirm:

```dart
  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    final passwordController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.settingsDeleteAccount),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This action cannot be undone. Enter your password to confirm.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.l10n.settingsCancel),
          ),
          TextButton(
            onPressed: () async {
              final password = passwordController.text;
              if (password.isEmpty) return;
              Navigator.pop(dialogContext);
              final ok = await ref
                  .read(currentUserProvider.notifier)
                  .deleteAccount(password: password);
              if (ok) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Account deleted')),
                );
                await ref.read(authProvider.notifier).logout();
              } else {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Could not delete account. Check your password.'),
                  ),
                );
              }
            },
            child: Text(context.l10n.settingsDelete,
                style: TextStyle(color: AppTheme.errorColor)),
          ),
        ],
      ),
    );
  }
```

This removes the `// TODO: Call delete account API` and the fake "Account deletion requested"
SnackBar. On success the user is deleted, logged out, and the app routes to the welcome/login screen
(the router watches `authProvider`).

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/screens/settings/settings_screen.dart`
Expected: No new issues — in particular no `use_build_context_synchronously` (the messenger is
captured before the dialog; only the captured messenger and `ref` are used after the await).

- [ ] **Step 3: Commit**

```bash
git add lib/screens/settings/settings_screen.dart
git commit -m "feat(account): wire real account deletion in settings

Confirm now calls deleteAccount(password); on success shows feedback and
logs out (routing to welcome), on failure surfaces a real error. Replaces
the TODO stub that faked success. Fixes the defunct-dialog-context use."
```

---

### Task 3: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Full test suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 2: Analyze the project**

Run: `flutter analyze`
Expected: No NEW issues in the two files this phase touched. Pre-existing unrelated lints acceptable.

- [ ] **Step 3: Commit any fixups**

```bash
git add lib/providers/user_provider.dart lib/screens/settings/settings_screen.dart && git commit -m "fixup: phase-6a account deletion"
```

(Skip if nothing needed. Stage ONLY the two phase files.)

---

## Self-Review

**Spec coverage (spec §6-R):** in-app account deletion → Tasks 1-2 (wired to the real service, with
logout + routing). ✅ Age gate → already satisfied by `min: 18` on the registration slider, recorded,
no work. ✅

**Placeholder scan:** No TBD/TODO — this plan REMOVES the existing TODO stub. Concrete code for every
step. ✅

**Type consistency:** `deleteAccount({required String password}) -> Future<bool>` matches across the
provider definition, the test, and the Task 2 call site. `UserService.deleteAccount({required String
password, String? reason})` matches `user_service.dart`. `logout()` is `Future<void>` on the auth
notifier. `clearUser()` sets `AsyncValue.data(null)`, which the test asserts via `state.value == null`.
✅

**Context-safety:** the messenger is captured from the screen context before `showDialog`; the confirm
handler uses only that captured messenger and `ref` after its await — no dialog context across the gap.
✅
