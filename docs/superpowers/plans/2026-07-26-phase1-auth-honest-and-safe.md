# Phase 1 — Auth: Honest & Safe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the auth surface honest and safe for a production deploy: remove the registration dead-end, hide features with no backend (social login, forgot-password), store tokens securely, and stop leaking tokens/PII to release logs.

**Architecture:** Small, surgical changes across four files plus a pubspec dependency. Two new compile-time feature flags on `EnvConfig` gate the unbuilt features so they can be flipped back on when their backends ship. Token persistence moves from plaintext `SharedPreferences` to `flutter_secure_storage`, with a one-time migration so existing logged-in users are not logged out on upgrade.

**Tech Stack:** Flutter, Dart, Riverpod, `flutter_test`. New dependency: `flutter_secure_storage`.

## Global Constraints

- API base (prod): `https://api.banatalk.com/flamebackend/v1`. The prod backend implements only `/auth/{register,login,refresh,logout}` — NOT `/auth/verify-email`, `/auth/forgot-password`, or `/auth/{google,apple,facebook}`.
- Login is the primary path and MUST keep working (email + password → tokens). Do not change `AuthService.login`, `AuthNotifier.login`, or the token-refresh machinery (`api_client.dart:227-334`).
- Hidden features are gated by a flag, not deleted — so they can be re-enabled when their backend lands. Default the flags OFF in every environment for this MVP.
- Do not change `User`'s shape or `User.fromJson` (Phase 2 owns that).
- Commands: `flutter test <path>`, `flutter analyze <paths>`, `flutter pub get`.
- Existing test to keep green: `test/services/api_client_refresh_test.dart` (token-refresh mutex).

**Empirically verified (2026-07-26):** login returns `{ user, tokens:{accessToken,refreshToken,expiresIn} }`; register returns tokens immediately with no verification gate; there is no email/code delivery.

**Out of scope for this plan (tracked, not executed here):**
- **Item G — real legal copy.** `legal_document_sheet.dart` renders lorem-ipsum ToS/Privacy. Replacing it needs counsel-approved text (a content deliverable), not code. It MUST be done before store submission but is not a task in this plan. See the "Manual follow-ups" section.
- Social token-parse dual-casing (`auth_service.dart:245,283,319`): these methods are only reached through the social buttons, which Task 2 hides. Dead in prod once hidden, so the fix rides along with re-enabling social later, not now.

---

### Task 1: Remove the email-verification dead-end from registration

**Problem:** After a successful `register()` the backend already issued tokens, but the flow
pushes `StepVerifyEmail`, which POSTs to non-existent `/auth/verify-email`; every code entry
fails and the user cannot advance (`registration_flow.dart:260-264,376-378`).

**Fix:** Registration ends at the photos step. On successful register, mark the flow complete;
the existing `ref.listen` (`registration_flow.dart:77-80`) pops to root when
`isAuthenticated && _registrationComplete`.

**Files:**
- Modify: `lib/screens/auth/registration/registration_flow.dart`
- Test: `test/screens/auth/registration_no_verify_step_test.dart` (create)

**Interfaces:**
- Consumes: `authProvider` (`AuthState.isAuthenticated`), the existing `ref.listen` pop-to-root.
- Produces: registration flow with `_totalSteps == 5`, ending on `StepPhotos`. `StepVerifyEmail`
  is no longer instantiated. `RegistrationData`'s public shape is unchanged.

- [ ] **Step 1: Write the failing test**

Create `test/screens/auth/registration_no_verify_step_test.dart`. Use the SAME localization
harness as the existing `test/screens/auth/registration_consent_test.dart` (verified pattern:
`kSupportedLocales` + `AppLocalizations.delegate` + Global delegates, locale `en`, wrapped in
`ProviderScope` because `RegistrationFlow` reads `authProvider`). The discriminating assertion:
the header reads "Step 1 of 5", not "of 6".

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';

Widget _host(Widget home) => ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: kSupportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );

void main() {
  testWidgets('registration has 5 steps and no verify-email step', (tester) async {
    await tester.pumpWidget(_host(const RegistrationFlow()));
    await tester.pump();

    // Header shows total step count.
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.text('Step 1 of 6'), findsNothing);

    // The verify-email subtitle is never shown as a step.
    expect(find.text('Enter the code we sent you'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/auth/registration_no_verify_step_test.dart`
Expected: FAIL — currently "Step 1 of 6".

- [ ] **Step 3: Implement**

In `lib/screens/auth/registration/registration_flow.dart`:

1. `_totalSteps`: change `6` → `5`. Update the comment (`// 5-step flow; no email verification`).
2. Remove the last entry (`'Verify Email'`) from `_stepTitles` and the last entry
   (`'Enter the code we sent you'`) from `_stepSubtitles`.
3. In `_buildPageView`, delete the `StepVerifyEmail( ... )` child (the 6th child, lines 260-264).
4. In `_handleBack`, delete the `if (_currentStep == 5) { _showCancelDialog(); return; }` block
   (lines 271-275) — there is no un-leaveable step anymore.
5. In `_handlePhotosComplete`, replace the success branch (lines 376-379):

```dart
      if (success) {
        // Registration is complete — tokens are already issued. The ref.listen
        // above pops to root once auth state flips to authenticated.
        setState(() => _registrationComplete = true);
      }
```

6. Delete the now-unused members: `_showCancelDialog` (285-309), `_handleEmailVerified`
   (503-506), `_handleResendCode` (508-520).
7. Remove the import `import 'steps/step_verify_email.dart';` (line 17).

Leave everything else (photo upload, compression, location, progress UI) unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/auth/registration_no_verify_step_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze (catch any unused-symbol leftovers)**

Run: `flutter analyze lib/screens/auth/registration/registration_flow.dart`
Expected: No issues — no "unused element" warnings for the removed handlers/import.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/auth/registration/registration_flow.dart test/screens/auth/registration_no_verify_step_test.dart
git commit -m "fix(auth): remove email-verify dead-end from registration

Backend issues tokens immediately and has no /auth/verify-email; the flow
now ends at the photos step and pops to root on successful register. Drops
the unreachable StepVerifyEmail, cancel dialog, and resend handlers."
```

---

### Task 2: Hide social login and forgot-password behind feature flags

**Problem:** Login shows Google/Apple/Facebook buttons and a Forgot-Password link, all of which
call non-existent endpoints (`auth_service.dart:175,237,275,311`).

**Fix:** Add two OFF-by-default flags to `EnvConfig` and gate the UI on them.

**Files:**
- Modify: `lib/config/env.dart`
- Modify: `lib/screens/auth/login_screen.dart`
- Test: `test/config/env_flags_test.dart` (create)
- Test: `test/screens/auth/login_hidden_features_test.dart` (create)

**Interfaces:**
- Produces: `EnvConfig.authSocialEnabled` (bool) and `EnvConfig.forgotPasswordEnabled` (bool),
  both `false` in `_local` and `_prod`. Login screen renders social block / forgot link only
  when the corresponding flag is true.

- [ ] **Step 1: Write the failing tests**

Create `test/config/env_flags_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/config/env.dart';

void main() {
  test('social login and forgot-password are OFF by default (MVP)', () {
    expect(EnvConfig.current.authSocialEnabled, isFalse);
    expect(EnvConfig.current.forgotPasswordEnabled, isFalse);
  });
}
```

Create `test/screens/auth/login_hidden_features_test.dart`. Same localization harness as Task 1.
The exact English strings (verified in `lib/l10n/app_en.arb`) are `loginOrContinueWith` = "Or
continue with" and `loginForgotPassword` = "Forgot password?". Assert both are absent while the
core login form still renders:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/screens/auth/login_screen.dart';

Widget _host(Widget home) => ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: kSupportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    );

void main() {
  testWidgets('social login and forgot-password are hidden in MVP', (tester) async {
    await tester.pumpWidget(_host(const LoginScreen()));
    await tester.pump();

    // Core login still present.
    expect(find.byType(TextFormField), findsWidgets);

    // Hidden features absent (exact l10n English strings).
    expect(find.text('Or continue with'), findsNothing);
    expect(find.text('Forgot password?'), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/config/env_flags_test.dart test/screens/auth/login_hidden_features_test.dart`
Expected: FAIL — flags don't exist (compile error) / social + forgot are currently shown.

- [ ] **Step 3: Implement the flags**

In `lib/config/env.dart`, add two fields to `EnvConfig` and its const constructor, defaulting
false, and set them (implicitly false) in `_local` and `_prod`:

```dart
  /// Whether social login (Google/Apple/Facebook) is shown. The Flame backend
  /// has no social auth endpoints yet — off until they ship.
  final bool authSocialEnabled;

  /// Whether the forgot-password flow is shown. No /auth/forgot-password on the
  /// backend yet — off until it ships.
  final bool forgotPasswordEnabled;

  const EnvConfig._(this.env, this.apiBase, this.wsBase,
      {this.realtimeEnabled = true,
      this.authSocialEnabled = false,
      this.forgotPasswordEnabled = false});
```

`_local` and `_prod` need no new arguments — the defaults (false) apply. Leave `realtimeEnabled`
values as they are.

- [ ] **Step 4: Implement the gating in login_screen**

In `lib/screens/auth/login_screen.dart`:

1. Add the import: `import 'package:flame/config/env.dart';` (if not already present).
2. At the call site of `_buildSocialLogin()` (around line 113), gate it:

```dart
                  if (EnvConfig.current.authSocialEnabled) _buildSocialLogin(),
```

3. In `_buildRememberForgot()` (line 315), wrap the forgot-password `TextButton` (lines 343-359)
   so it renders only when enabled, preserving the Row layout:

```dart
        if (EnvConfig.current.forgotPasswordEnabled)
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ForgotPasswordScreen(),
                ),
              );
            },
            child: Text(
              context.l10n.loginForgotPassword,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
          )
        else
          const SizedBox.shrink(),
```

Leave the social handler methods (`_handleGoogleSignIn`, etc.) and `SocialProfileCompletionFlow`
in place — dead but harmless while the flag is off; they return when social is re-enabled.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/config/env_flags_test.dart test/screens/auth/login_hidden_features_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/config/env.dart lib/screens/auth/login_screen.dart`
Expected: No new issues. (Pre-existing `withOpacity` deprecation lints in this file are not in
scope — do not fix them here.)

- [ ] **Step 7: Commit**

```bash
git add lib/config/env.dart lib/screens/auth/login_screen.dart test/config/env_flags_test.dart test/screens/auth/login_hidden_features_test.dart
git commit -m "feat(auth): gate social login and forgot-password behind flags

Both call endpoints the backend doesn't implement. New EnvConfig flags
authSocialEnabled / forgotPasswordEnabled (OFF for MVP) hide them without
deleting the code, so they flip back on when their backends ship."
```

---

### Task 3: Store auth tokens in secure storage (with migration)

**Problem:** Access + refresh tokens are persisted in plaintext `SharedPreferences`
(`api_client.dart:47-80`).

**Fix:** Persist the three token keys via `flutter_secure_storage` (Keychain/Keystore). On first
run after upgrade, migrate any legacy plaintext tokens so existing users stay logged in.

**Files:**
- Modify: `pubspec.yaml` (add dependency)
- Modify: `lib/services/api_client.dart` (`init`, `saveTokens`, `clearTokens`)
- Test: `test/services/token_storage_test.dart` (create)

**Interfaces:**
- Consumes: existing private key constants `_accessTokenKey`, `_refreshTokenKey`, `_userIdKey`
  and fields `_accessToken`, `_refreshToken`, `_userId` in `ApiClient`.
- Produces: `ApiClient.init()` reads tokens from secure storage (migrating from SharedPreferences
  once); `saveTokens()` writes to secure storage; `clearTokens()` deletes from secure storage and
  purges legacy prefs keys. Public API (`hasTokens`, `accessToken`, `saveTokens`, `clearTokens`,
  `init`) signatures unchanged.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:` (near `shared_preferences: ^2.2.3`), add:

```yaml
  flutter_secure_storage: ^9.2.2
```

Run: `flutter pub get`
Expected: resolves successfully. Note the resolved version in the commit body.

- [ ] **Step 2: Write the failing test**

Create `test/services/token_storage_test.dart`. Use the package's in-memory test mock and the
SharedPreferences mock. Confirm the exact mock-setup API against the resolved
`flutter_secure_storage` version (v9 exposes `FlutterSecureStorage.setMockInitialValues`); if the
installed version's helper differs, adapt the setup — the assertions stay the same.

```dart
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  http.Client _noNet() =>
      MockClient((req) async => http.Response('{}', 200));

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('saveTokens persists to secure storage and reloads via init', () async {
    final a = ApiClient.testInstance(httpClient: _noNet());
    await a.saveTokens(accessToken: 'AT', refreshToken: 'RT', userId: 'u1');

    final b = ApiClient.testInstance(httpClient: _noNet());
    await b.init();
    expect(b.accessToken, 'AT');
    expect(b.hasTokens, isTrue);
  });

  test('migrates legacy SharedPreferences tokens on init, then clears prefs', () async {
    SharedPreferences.setMockInitialValues({
      'access_token': 'LEGACY_AT',
      'refresh_token': 'LEGACY_RT',
      'user_id': 'legacyUser',
    });
    final a = ApiClient.testInstance(httpClient: _noNet());
    await a.init();
    expect(a.accessToken, 'LEGACY_AT');

    // Legacy prefs are purged after migration.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), isNull);

    // And they now live in secure storage.
    const secure = FlutterSecureStorage();
    expect(await secure.read(key: 'access_token'), 'LEGACY_AT');
  });

  test('clearTokens removes tokens from secure storage', () async {
    final a = ApiClient.testInstance(httpClient: _noNet());
    await a.saveTokens(accessToken: 'AT', refreshToken: 'RT');
    await a.clearTokens();
    expect(a.hasTokens, isFalse);
    const secure = FlutterSecureStorage();
    expect(await secure.read(key: 'access_token'), isNull);
  });
}
```

The exact prefs key strings (`access_token`, `refresh_token`, `user_id`) must match the values
of `_accessTokenKey` / `_refreshTokenKey` / `_userIdKey` in `api_client.dart` — read those
constants and use their literal values in the test.

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/services/token_storage_test.dart`
Expected: FAIL — tokens still go to SharedPreferences; migration + secure read not implemented.

- [ ] **Step 4: Implement**

In `lib/services/api_client.dart`:

1. Add import: `import 'package:flutter_secure_storage/flutter_secure_storage.dart';`
2. Add an instance field (works for both the singleton and `testInstance`):

```dart
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
```

3. Replace `init()` (lines 48-53) with secure read + one-time migration:

```dart
  Future<void> init() async {
    _accessToken = await _secureStorage.read(key: _accessTokenKey);
    _refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    _userId = await _secureStorage.read(key: _userIdKey);

    // One-time migration from legacy plaintext SharedPreferences.
    if (_accessToken == null) {
      final prefs = await SharedPreferences.getInstance();
      final legacyAccess = prefs.getString(_accessTokenKey);
      final legacyRefresh = prefs.getString(_refreshTokenKey);
      if (legacyAccess != null && legacyRefresh != null) {
        _accessToken = legacyAccess;
        _refreshToken = legacyRefresh;
        _userId = prefs.getString(_userIdKey);
        await _secureStorage.write(key: _accessTokenKey, value: legacyAccess);
        await _secureStorage.write(key: _refreshTokenKey, value: legacyRefresh);
        if (_userId != null) {
          await _secureStorage.write(key: _userIdKey, value: _userId!);
        }
        await prefs.remove(_accessTokenKey);
        await prefs.remove(_refreshTokenKey);
        await prefs.remove(_userIdKey);
      }
    }
  }
```

4. Replace the storage writes in `saveTokens()` (lines 65-68) with:

```dart
    await _secureStorage.write(key: _accessTokenKey, value: accessToken);
    await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
    if (userId != null) {
      await _secureStorage.write(key: _userIdKey, value: userId);
    }
```

(Keep the in-memory assignments at the top of `saveTokens` unchanged.)

5. Replace the storage removes in `clearTokens()` (lines 76-79) with secure deletes plus a
   legacy-prefs purge:

```dart
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _userIdKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userIdKey);
```

Keep the `SharedPreferences` import (still used for migration + purge). Do not touch the
token-refresh logic.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/services/token_storage_test.dart`
Expected: PASS (all three tests).

- [ ] **Step 6: Guard the refresh test still passes**

Run: `flutter test test/services/api_client_refresh_test.dart`
Expected: PASS — the refresh mutex is untouched. If it now needs
`FlutterSecureStorage.setMockInitialValues({})` in its setUp to avoid a platform-channel error,
add exactly that line and note it in the commit.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/services/api_client.dart test/services/token_storage_test.dart
git commit -m "feat(auth): store tokens in flutter_secure_storage with migration

Access/refresh/userId move from plaintext SharedPreferences to Keychain/
Keystore. init() migrates legacy plaintext tokens once so upgrading users
stay logged in; clearTokens() also purges any legacy prefs keys."
```

---

### Task 4: Stop leaking tokens/PII to release logs

**Problem:** `_handleResponse` uses bare `print()` to dump the response body (which for
login/register/`/users/me` contains tokens + PII) in release builds
(`api_client.dart:440,445,449,508`).

**Fix:** Gate the diagnostic logging behind `kDebugMode` so nothing prints in release, and stop
printing full response bodies at all.

**Files:**
- Modify: `lib/services/api_client.dart`
- Verify: no runtime unit test (log gating is a compile-time constant); verified by analyze + a
  source check.

**Interfaces:** none changed — internal logging only.

- [ ] **Step 1: Implement**

In `lib/services/api_client.dart`:

1. Ensure `import 'package:flutter/foundation.dart';` is present (for `kDebugMode`); add it if not.
2. Line 440 — gate the status line and drop the URL/body detail to method + status only:

```dart
    if (kDebugMode) {
      print('API Response: ${response.request?.method} $statusCode');
    }
```

3. Lines 443-450 — remove the two body-dumping `print` calls. Keep the `jsonDecode`; only the
   logging goes:

```dart
    try {
      if (response.body.isNotEmpty) {
        data = jsonDecode(response.body);
      }
    } catch (e) {
      // Response is not JSON; body intentionally not logged (may contain PII).
    }
```

4. Line 508 — gate the error log (status + code only, no body):

```dart
    if (kDebugMode) {
      print('API Error: $statusCode ${errorCode ?? ''}');
    }
```

Do not change any control flow or the returned `ApiResponse` objects.

- [ ] **Step 2: Verify no ungated body logging remains**

Run: `grep -nE "print\('API Response Body|print\('API Response \(non-JSON" lib/services/api_client.dart`
Expected: no matches (both body/`non-JSON` prints are gone).

Run: `grep -nE "print\(" lib/services/api_client.dart`
Expected: only the two `kDebugMode`-guarded prints remain (status line + error line); no bare
top-level `print(` outside a `kDebugMode` guard.

- [ ] **Step 3: Analyze + full suite**

Run: `flutter analyze lib/services/api_client.dart`
Expected: No new issues.

Run: `flutter test test/services/`
Expected: PASS — refresh + token-storage + translation service tests still green.

- [ ] **Step 4: Commit**

```bash
git add lib/services/api_client.dart
git commit -m "fix(security): gate API logging behind kDebugMode, stop logging bodies

Release builds no longer print response bodies (which carried tokens and
PII for login/register//users/me). Remaining diagnostics are debug-only and
log method/status/code without body content."
```

---

### Task 5: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Full test suite**

Run: `flutter test`
Expected: PASS (all suites). If a pre-existing registration/login test asserted the old
6-step/social/forgot behavior, update that assertion to the new behavior and note it in the
commit.

- [ ] **Step 2: Analyze the project**

Run: `flutter analyze`
Expected: No new issues introduced by this phase (pre-existing lints unrelated to these files are
acceptable).

- [ ] **Step 3: Commit any test fixups**

```bash
git add -A
git commit -m "test: update auth assertions for honest-MVP behavior"
```

(Skip if Step 1 required no changes.)

---

## Manual follow-ups (not executed by this plan)

- **Item G — legal copy.** Replace the lorem-ipsum ToS/Privacy in
  `lib/screens/auth/registration/legal_document_sheet.dart:88-178` (and remove its placeholder
  banner) with finalized, counsel-approved text. Blocked on content from the product owner. Must
  ship before store submission.

## Self-Review

**Spec coverage (Phase 1, spec §5 C-G):**
- C (remove verify dead-end) → Task 1. ✅
- D (hide social + forgot; park social-completion) → Task 2 (flags + gating; completion flow left
  dead-but-unreachable, which satisfies "park"). ✅
- E (secure token storage) → Task 3. ✅
- F (strip PII/token logs) → Task 4. ✅
- G (legal copy) → tracked in Manual follow-ups; not a code task (needs counsel copy). ✅ (deferred by design)

**Placeholder scan:** No TBD/TODO/"handle edge cases". Task 3 flags one real uncertainty (the
secure-storage test-mock API name across package versions) with a concrete instruction to confirm
against the resolved version — not a placeholder. ✅

**Type consistency:** `EnvConfig.authSocialEnabled` / `forgotPasswordEnabled` are defined in Task 2
and used with identical names in the gating and tests. Token key constants (`_accessTokenKey` etc.)
are referenced by their literal prefs values in the Task 3 test, matching `api_client.dart`. Public
`ApiClient` method signatures are unchanged across Task 3 and Task 4. ✅
