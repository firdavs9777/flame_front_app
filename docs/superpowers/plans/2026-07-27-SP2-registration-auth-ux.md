# SP2 — Registration + Auth-UX Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. For the UI-polish task, also apply superpowers:frontend-design principles. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Align the Flutter app to the (SP1-fixed) backend auth contract, make registration fail-fast + resilient + resumable + lighter, and bring the welcome/login/registration screens onto the Phase-A design system with real Google/Apple/Facebook buttons (gated by `authSocialEnabled`).

**Architecture:** Frontend-only (this repo). Logic changes (contract, fail-fast, parallel upload, draft persistence) get exact code + unit/widget tests. UI polish reuses the existing `widgets/kit` (`AppInput`, `AppButton`, `AppCard`) + `AppTheme` tokens. Everything social stays behind `EnvConfig.authSocialEnabled` (still `false` until SP1 is deployed + keys set).

**Tech Stack:** Flutter, Riverpod, `shared_preferences`, `google_sign_in`/`sign_in_with_apple`/`flutter_facebook_auth` (already in `pubspec.yaml`), `flutter_test` + `http`'s `MockClient` (existing test pattern).

## Global Constraints
- Repo `/Users/firdavsmutalipov/Desktop/Flame/flame_front_app`, branch `feat/phase-a-visual-foundation` (current). Never `main`.
- **Preserve in-flight work:** the working tree already has uncommitted edits to `lib/services/auth_service.dart` (token dual-casing), `lib/screens/auth/registration/steps/step_email_password.dart` (consent row), `lib/providers/auth_provider.dart`, `lib/widgets/profile_card.dart`, and the `lib/l10n/*.arb` + story files. These are legitimate related work — build ON TOP of them; do not revert them. Commit them as part of coherent SP2 commits where they belong (they are auth/registration-related), but never discard them.
- Backend auth `/auth/*` emits **camelCase** token keys (`accessToken`,`refreshToken`); `/auth/check-email` returns `{success:true, data:{available:bool}}`; social endpoints accept snake bodies (`id_token`,`access_token`,`authorization_code`,`device_token`) and return `{data:{user,tokens,is_new_user}}`. `register` accepts `lookingFor` (camel) + optional `latitude`,`longitude`,`photos` (url strings).
- Existing conventions: `ApiClient` is injectable via constructor (see `NotificationSettingsService`); `ServiceResult<T>` from `user_service.dart`; kit widgets under `lib/widgets/kit/kit.dart`; theme tokens `AppColors`/`AppTypography`/`AppRadius`/`AppTheme` in `lib/theme/app_theme.dart`; context-safety pattern (capture messenger/navigator before await, `if(!context.mounted)return;`); flutter analyze must be clean; `flutter test` all green.
- Social UI renders ONLY when `EnvConfig.current.authSocialEnabled` is true. Do NOT flip the flag in this plan (that's a go-live step after SP1 deploys).

---

### Task 1: Backend-contract alignment (register + social token parse)

**Files:** Modify `lib/services/auth_service.dart`; Test `test/services/auth_service_contract_test.dart` (create).

**Interfaces:** Produces: `register(...)` sends `lookingFor` (camel) + `latitude`/`longitude`/`photos`; `googleSignIn`/`appleSignIn`/`facebookSignIn` read camelCase tokens first.

- [ ] **Step 1:** In `auth_service.dart` `register(...)`, change the body key `'looking_for': lookingFor.toApiString()` → `'lookingFor': lookingFor.toApiString()`. Leave `latitude`/`longitude`/`photos` as-is (backend now accepts them).
- [ ] **Step 2:** In `googleSignIn`, `appleSignIn`, `facebookSignIn`, change the token reads from snake-only to camel-first dual-casing (mirroring the already-fixed login/register):
  ```dart
  accessToken: tokens['accessToken'] ?? tokens['access_token'],
  refreshToken: tokens['refreshToken'] ?? tokens['refresh_token'],
  ```
- [ ] **Step 3: Tests** (MockClient, like `test/services/notification_settings_service_test.dart`): a `register(...)` call sends a body whose JSON contains `"lookingFor"` and NOT `"looking_for"`, and includes `latitude`/`longitude`/`photos`; a `googleSignIn` against a response with camelCase `tokens.accessToken` saves the token (assert via a stub ApiClient capturing `saveTokens`, or assert `AuthResult.success`). Note: `AuthService` currently news-up its own `ApiClient()` (not injectable) — refactor `AuthService` to accept an optional `ApiClient` in its constructor (`AuthService({ApiClient? apiClient})`), defaulting to `ApiClient()`, so it can be tested; update call sites if the constructor is used positionally (it is used as `AuthService()` — safe).
- [ ] **Step 4:** `flutter test test/services/auth_service_contract_test.dart` green; `flutter analyze lib/services/auth_service.dart` clean.
- [ ] **Step 5: Commit** `fix(auth): align register+social parse to backend contract (lookingFor, camel tokens)`.

---

### Task 2: Email availability service + fail-fast at step 1

**Files:** Create `lib/services/auth_availability_service.dart`, `lib/providers/auth_availability_provider.dart`; Modify `lib/screens/auth/registration/steps/step_email_password.dart`; Test `test/services/auth_availability_service_test.dart`, `test/screens/auth/step_email_password_test.dart`.

**Interfaces:** Produces `AuthAvailabilityService.checkEmail(String) → Future<ServiceResult<bool>>` (true = available).

- [ ] **Step 1: `auth_availability_service.dart`** (injectable ApiClient):
  ```dart
  import 'package:flame/services/api_client.dart';
  import 'package:flame/services/user_service.dart' show ServiceResult;

  class AuthAvailabilityService {
    final ApiClient _apiClient;
    AuthAvailabilityService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

    /// Returns whether [email] is available (not already registered).
    Future<ServiceResult<bool>> checkEmail(String email) async {
      final response = await _apiClient.post('/auth/check-email', body: {'email': email});
      if (response.success && response.data != null) {
        return ServiceResult.success(response.data['available'] == true);
      }
      return ServiceResult.failure(response.error ?? 'Could not check email');
    }
  }
  ```
- [ ] **Step 2: provider** exposing the service (overridable in tests), mirroring `notificationSettingsServiceProvider`.
- [ ] **Step 3:** Wire fail-fast into `StepEmailPassword`. Convert the widget to a `ConsumerStatefulWidget` (it currently extends `StatefulWidget`). In `_handleContinue`: after `_formKey.currentState!.validate()` passes, set a `_checking=true` state (disable the button + show `AppButton(isLoading:true)`), call `ref.read(authAvailabilityServiceProvider).checkEmail(email)`:
  - available `true` → save data + `widget.onNext()`.
  - available `false` → set an inline email error (`_emailAvailabilityError = 'That email is already registered'`) shown under the field; do NOT advance. Offer a "Log in instead" text button that pops to login.
  - `ServiceResult.failure` (network/unavailable) → **fail open**: proceed to next step (final `register()` still enforces uniqueness). Do not hard-block on a check-email outage.
  - Always clear `_checking` in a `finally`. Use the context-safety pattern.
- [ ] **Step 4: Tests.** Service test (MockClient): `available:true`→success(true); `available:false`→success(false); non-200→failure. Widget test (`step_email_password_test.dart`) overriding `authAvailabilityServiceProvider` with a fake: entering a taken email + tapping Continue shows the inline error and does NOT call `onNext`; an available email calls `onNext`; a failing check still calls `onNext` (fail-open).
- [ ] **Step 5:** `flutter test` (the two new files) green; `flutter analyze` clean on changed files.
- [ ] **Step 6: Commit** `feat(register): fail-fast email availability check at step 1`.

---

### Task 3: Parallel + resilient photo upload

**Files:** Create `lib/screens/auth/registration/photo_uploader.dart` (extracted, testable); Modify `lib/screens/auth/registration/registration_flow.dart`; Test `test/screens/auth/photo_uploader_test.dart`.

**Interfaces:** Produces `PhotoUploader` with `Future<List<String>> upload(List<File> files, {required Future<UploadOutcome> Function(File file, {required bool isPrimary}) uploadOne})` — order-preserving, bounded concurrency, 1 retry per file. `UploadOutcome({bool success, String? url})`.

- [ ] **Step 1:** Extract the current serial loop into `PhotoUploader.upload(...)` taking an injected `uploadOne` callback (so tests don't hit the network). Implement: map each file (with its index → `isPrimary = index==0`) to a future that calls `uploadOne` and retries ONCE on failure; run with a small concurrency bound (e.g. `Future.wait` over all — the count is ≤6, so unbounded `Future.wait` is fine); collect results **in original index order**; drop failures (after retry) but keep the successful URLs in order. Return the URL list.
- [ ] **Step 2:** In `registration_flow.dart`, replace the body of `_uploadPhotosForRegistration` to build a `PhotoUploader` and pass an `uploadOne` that does the existing compress + `userService.uploadPhotoForRegistration(compressed, isPrimary: isPrimary)` and maps to `UploadOutcome`. Keep the compression logic. Preserve the existing empty-list short-circuit and debug logging.
- [ ] **Step 3: Tests** (`photo_uploader_test.dart`, no real files needed — pass dummy `File` objects and a fake `uploadOne`): 3 files all succeed → 3 URLs in order, index0 flagged primary (assert the fake received `isPrimary:true` for the first); a middle file fails once then succeeds on retry → still 3 URLs in order; a file fails twice → that URL omitted, others preserved in order.
- [ ] **Step 4:** `flutter test test/screens/auth/photo_uploader_test.dart` green; analyze clean.
- [ ] **Step 5: Commit** `feat(register): parallel photo upload with per-photo retry`.

---

### Task 4: Draft persistence / resume

**Files:** Create `lib/screens/auth/registration/registration_draft.dart`; Modify `registration_flow.dart`; Test `test/screens/auth/registration_draft_test.dart`.

**Interfaces:** Produces `RegistrationDraft` with `toJson(RegistrationData)`, `RegistrationData fromJson(Map)`, `Future<void> save(RegistrationData, int step)`, `Future<({RegistrationData data, int step})?> load()`, `Future<void> clear()` — backed by `shared_preferences` under key `registration_draft`. Persists scalar fields + `photoFiles` as file paths (skip URLs list); does NOT persist raw bytes.

- [ ] **Step 1:** Implement `RegistrationDraft`. Serialize `email,name,age,gender(index/name),lookingFor,bio,interests,latitude,longitude, photoFilePaths:[...], step`. On `load`, reconstruct `RegistrationData` (rehydrate `photoFiles` from existing paths that still exist on disk; skip missing). Gender enums via `.name`.
- [ ] **Step 2:** In `registration_flow.dart`: on each `_goToNextStep`/`onPageChanged`, call `draft.save(_data, _currentStep)` (fire-and-forget, guarded). In `initState`, `draft.load()`; if a draft exists, show a lightweight "Resume your signup?" dialog/banner — Resume restores `_data` + jumps to the saved step; Start Over clears the draft. On successful registration and on explicit cancel/back-out to login, `draft.clear()`.
- [ ] **Step 3: Tests** (`registration_draft_test.dart`, `SharedPreferences.setMockInitialValues({})`): save→load round-trips all scalar fields + step; `clear()` empties it; `load()` with no draft returns null; a draft with a non-existent photo path drops that path without throwing.
- [ ] **Step 4:** `flutter test test/screens/auth/registration_draft_test.dart` green; analyze clean.
- [ ] **Step 5: Commit** `feat(register): persist + resume registration draft`.

---

### Task 5: Lighter steps (skippable bio; streamlined interests)

**Files:** Modify `lib/screens/auth/registration/steps/step_bio_interests.dart` (+ possibly `registration_flow.dart` step copy).

- [ ] **Step 1:** Make **bio** explicitly optional: add a "Skip for now" text action on the bio/interests step that advances without requiring bio text (bio already `optional` on the backend). Keep interests at **≥1** (backend `registerSchema` requires `interests.min(1)`) but make selecting fast — pre-surface common interests as tappable chips and enable Continue as soon as one is chosen; show a clear helper ("Pick at least one — you can add more later").
- [ ] **Step 2:** Ensure the required dating fields (name/age/gender/lookingFor) remain required (do not make those skippable). Update the step subtitle copy in `registration_flow.dart` if it implies bio is required.
- [ ] **Step 3: Test / verify:** a widget test (or extend an existing step test) asserting the bio step's Continue is enabled with ≥1 interest and no bio; and that "Skip for now" advances. If a full widget test is impractical for this step, assert the enable-logic via a small extracted predicate + unit test.
- [ ] **Step 4:** analyze clean; `flutter test` green.
- [ ] **Step 5: Commit** `feat(register): optional bio + streamlined interests step`.

---

### Task 6: UI polish — welcome / login / register onto the design system + social buttons

**Files:** Modify `lib/screens/auth/welcome_screen.dart`, `lib/screens/auth/login_screen.dart`, the registration step cards (`steps/*.dart`) and `registration_flow.dart` chrome; Create `lib/widgets/auth/social_sign_in_buttons.dart`; Test `test/screens/auth/auth_ui_smoke_test.dart`.

**Design intent (apply superpowers:frontend-design):** Keep Flame's warm coral→orange gradient brand. Standardize every input to `AppInput`, every button to `AppButton`, cards to `AppCard`, and spacing/radii/colors/typography to `AppTheme` tokens (`AppColors`, `AppTypography`, `AppRadius`) — replacing ad-hoc `TextFormField`/`ElevatedButton`/hardcoded greys currently in these screens. Consistent field heights, focus/error states, loading states, and 44pt+ tap targets. Tasteful, not flashy; preserve existing animations where they read well.

- [ ] **Step 1: `social_sign_in_buttons.dart`.** A `ConsumerWidget` that renders, ONLY when `EnvConfig.current.authSocialEnabled`, a column of provider buttons: Google (white bg, Google "G" mark, "Continue with Google"), Facebook (`#1877F2`), and **Apple per HIG** (black in light mode / white in dark, Apple logo, "Sign in with Apple"). Each button calls `SocialAuthService.signInWith*`, then on success `authProvider.socialLogin(...)` with the returned tokens, and surfaces errors via SnackBar. Show a per-button loading state. A `divider` "or" above it. When the flag is false, the widget returns `SizedBox.shrink()`.
- [ ] **Step 2: `welcome_screen.dart`.** Rebuild with the gradient hero + logo, a primary "Create account" `AppButton` and a secondary "Log in" `AppButton`, and `SocialSignInButtons()` beneath (auto-hidden while flag off). Remove hardcoded button styling.
- [ ] **Step 3: `login_screen.dart`.** Rebuild the form with `AppInput` (email, password with show/hide), an `AppButton(isLoading: authState.isLoading)` submit, the forgot-password link gated by `forgotPasswordEnabled`, and `SocialSignInButtons()`. Preserve existing login logic/validation and error SnackBars.
- [ ] **Step 4: registration step cards.** Migrate the step inputs (`step_email_password`, `step_profile_info`, `step_bio_interests`, etc.) to `AppInput`/`AppButton` and `AppTheme` tokens for visual consistency with login (keep their logic, incl. the Task-2 fail-fast and Task-1/5 changes). Keep the flow chrome (progress bar/header) but align colors/spacing to tokens.
- [ ] **Step 5: Smoke tests** (`auth_ui_smoke_test.dart`): welcome renders both primary/secondary buttons and (with `authSocialEnabled` forced true via a test EnvConfig seam, or by testing `SocialSignInButtons` directly) shows 3 provider buttons; with the flag false `SocialSignInButtons` renders nothing; login screen renders email+password `AppInput`s + submit. Keep tests to render/finder assertions (no real SDK calls).
- [ ] **Step 6:** `flutter analyze` clean across changed files; full `flutter test` green.
- [ ] **Step 7: Commit** `feat(auth-ui): welcome/login/register on design system + social buttons (flag-gated)`.

---

### Task 7: Full-suite verification
- [ ] `flutter analyze` (whole project) clean. `flutter test` (whole suite) green. Branch `feat/phase-a-visual-foundation`, tree committed. Confirm `authSocialEnabled` is still `false` in both `_local` and `_prod` (not flipped by this plan).

## Deferred (needs the user)
- Flip `authSocialEnabled: true` after SP1 backend is deployed + provider keys set (go-live step, activation runbook).
- Native config for Apple (Sign in with Apple capability + entitlement) and Facebook (`Info.plist` URL scheme, app id) — required before the buttons actually work on device.
- Counsel-approved legal copy in `legal_document_sheet.dart` (tracked separately).

## Self-Review
Contract fix + social parse are the true unblockers and are unit-tested. Fail-fast fails OPEN so a check-email outage never blocks signup. Photo upload + draft + step logic are extracted into testable units so they don't require the network or a device. UI polish reuses the existing kit (no new design language) and keeps everything social behind the flag, so shipping SP2 changes nothing user-visible until go-live. In-flight uncommitted work is built upon, not reverted. ✅
