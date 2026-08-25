# Auth surface — bug fixes and structural cleanup

Twenty files, roughly 5,500 lines: `lib/screens/auth/**`, `lib/widgets/auth/`,
`lib/providers/auth_provider.dart`, `lib/providers/auth_availability_provider.dart`,
`lib/services/auth_service.dart`, `lib/services/auth_availability_service.dart`,
`lib/services/social_auth_service.dart`.

This is the last surface that has not had a scope of its own. Discover (A),
Profile / Settings / navigation (B) and notifications / email (C) all landed;
auth is the one every user touches first and the one nobody has been through
since it was written.

Confined to the app repository. One field is added to a backend-facing request
body, but the backend already accepts it — no server change is required.

## Why

**Registration can submit an empty password.** `RegistrationDraft` deliberately
never persists the password, which is correct. But `_restoreFrom`
(`registration_flow.dart:118`) jumps the resuming user straight to their saved
step, and step 0 is the only place a password is entered. Resume at step 2 or
later and `_data.password` stays `''` all the way into
`authProvider.register()`. The server's `registerSchema` requires
`z.string().min(8)`, so this is a 422 the user cannot diagnose or escape.

**Social sign-in silently discards gender.** `StepProfileInfo` collects it and
writes it to `_data.gender`. `SocialProfileCompletionFlow._handleComplete`
(`social_profile_completion_flow.dart:211`) calls `userService.updateProfile`,
whose signature (`user_service.dart:54`) has no `gender` parameter. The backend
added support in `378aa8f` — "allow age and gender in PATCH /v1/users/me for
social auth onboarding" — and the client never caught up. Every user who signs
up through Google keeps whatever gender the server defaulted them to.

**A `profileIncomplete` user is stranded on the login screen.** `LoginScreen` is
pushed over `home:` by `welcome_screen.dart:226`. Its `ref.listen`
(`login_screen.dart:39`) pops only on `next.isAuthenticated`. When a social
login resolves to `profileIncomplete`, `main.dart:88` swaps `home:` to
`SocialProfileCompletionFlow` underneath — and the pushed login screen stays on
top of it. The same shape sits in `registration_flow.dart:148`, gated behind
`_registrationComplete`.

**The email validator rejects valid addresses.** `^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$`,
copy-pasted verbatim into `login_screen.dart:223`,
`forgot_password_screen.dart:315` and `step_email_password.dart:141`. `\w`
excludes `+`, so every Gmail user who signs up with plus-addressing is turned
away at the door; `{2,4}` rejects `.museum`, `.travel` and `.online`.

**Six `setState` calls run after an `await` with no `mounted` guard** —
`registration_flow.dart:368`, `:382`, `:413`, `:423`, and
`social_profile_completion_flow.dart:221`, `:252`. Photo upload and registration
are the longest-running operations in the app and the easiest to back out of.

**The password rules contradict each other and the server.** Login demands six
characters (`login_screen.dart:247`), registration demands eight
(`step_email_password.dart:210`), and the checklist above the field
(`step_email_password.dart:237`) presents "one uppercase letter" and "one
number" as requirements that no validator and no server schema enforces.
Meanwhile the server's `max(128)` is enforced nowhere on the client, so a long
password 422s with no field-level message.

**Two flows are the same machine.** `RegistrationFlow` (552 lines) and
`SocialProfileCompletionFlow` (290 lines) share four of five steps, the header,
the progress indicator, the step-info block, the `PageView` and its
`NeverScrollableScrollPhysics`, and a near-identical private `_compressImage`.
They have already drifted: registration uploads photos through `PhotoUploader`
with a retry and parallel fan-out, the social flow uploads sequentially in a
`for` loop that swallows every error (`social_profile_completion_flow.dart:234`).
The dropped gender is the same drift.

**396 lines of the flow are unreachable.** `step_verify_email.dart` has zero
references in `lib/` or `test/`. It is the only caller of
`AuthService.verifyEmail` and `AuthService.resendVerificationCode`.
`AuthService.resetPassword` has no caller at all. `AuthStatus.registering`,
`AuthNotifier.startRegistration()` and `AuthNotifier.cancelRegistration()` are
never invoked — registration is a pushed route, not an auth status — and survive
only because `realtime_lifecycle_test.dart:44` enumerates the enum.

**`forgot_password_screen.dart` matches nothing else in the codebase.**
Deprecated `withOpacity` where every other file uses `withValues`, raw
`TextFormField` and `ElevatedButton` where the kit's `AppInput` and `AppButton`
exist, twelve hardcoded English strings, and `next.error!` printed straight to a
SnackBar instead of going through `translateApiError`. It is also unreachable —
`forgotPasswordEnabled` is `false` in both presets and the three password
endpoints do not exist server-side.

**Registration is un-localised.** Roughly 100 hardcoded English strings across
the flow and its five steps, against a login and welcome screen that read
entirely from ARBs.

**Fourteen SnackBars are hand-rolled** with the same
`AppTheme.errorColor` + floating + 12px-radius decoration, in a codebase that
already established `showChatSnackBar` and `showSettingsSnackBar` as the
pattern.

## Decisions taken

| Question | Decision |
|---|---|
| Scope | **Bugs and cleanup together.** The duplication is what produced the bugs; fixing one without the other invites the next drift. |
| The two flows | **One shared `StepWizard` shell.** Both flows become a step list plus a completion callback. |
| Login's password minimum | **Removed, not raised to eight.** Raising it would lock out any existing account with a six or seven character password. Strength rules belong at registration. |
| The uppercase / number checklist | **Demoted to advisory.** The server enforces length only; the checklist stops presenting hints as requirements. |
| Draft resume with no password | **Clamp the resume target to step 0.** The password still never touches disk. |
| `forgot_password_screen.dart` | **Rebuilt on the kit and localised, still behind the flag.** Ready when the endpoints land, and the codebase stops carrying an outlier. |
| Password self-service as a feature | **Out.** Still the open decision `RELEASE-CHECKLIST.md` records. |
| Dead code | **Deleted**, including the enum member the realtime test enumerates. |
| Translations | **New keys land in all twelve ARBs, with the English string as the placeholder value in the eleven non-English files.** ~~`app_en.arb` has 437 keys against 223 in the other eleven; Flutter falls back to English already.~~ That was wrong: the 437 came from a grep that counted the `"description"` lines inside `@key` blocks as keys. The twelve files are at parity, and `test/l10n/arb_parity_test.dart` enforces it. English placeholders are already the practice there. Translating them stays a separate content task. |
| `go_router` | **Out.** Unchanged from the navigation route table decision. |

## Architecture

### New shared units

Each has one job, a stated interface, and no dependency on the widget that uses
it.

**`lib/core/validation/auth_validators.dart`**

```dart
class AuthValidators {
  const AuthValidators(this.l10n);
  final AppLocalizations l10n;

  String? email(String? value);
  String? password(String? value);          // 8..128, mirrors registerSchema
  String? confirmPassword(String? value, String against);
  String? name(String? value);              // 2..50, mirrors registerSchema
  String? requiredField(String? value);     // login's password: presence only
}
```

Bounds live in one place and mirror `flame/routes/auth.js:12` exactly. The email
pattern becomes an HTML5-style expression accepting `+` addressing and TLDs of
any length. Depends only on `AppLocalizations`, so it unit-tests against the
generated `en` localisations with no widget tree.

**`lib/screens/auth/widgets/auth_snackbar.dart`** — `showAuthSnackBar(context,
message:, type:)` with an `AuthSnackBarType { info, error }`, following
`chat_snackbar.dart` and `settings_snackbar.dart` line for line, including their
`context.mounted` guard.

**`lib/screens/auth/widgets/auth_gradient_scaffold.dart`** — the
`FF6B6B → FF8E53` gradient, `SafeArea`, and the translucent rounded back button
currently duplicated across `login_screen`, `forgot_password_screen`,
`registration_flow` and `social_profile_completion_flow`. Takes a child and an
optional `onBack`.

**`lib/core/image/photo_compressor.dart`** — `PhotoCompressor.compress(File,
{required String tempDir, required int index})`, the 800px / JPEG-70 routine
lifted from both flows, beside `avatar_provider.dart`. Pure enough to test with
a generated image and no device.

### The wizard shell

**`lib/screens/auth/registration/step_wizard.dart`**

```dart
class WizardStep {
  final String title;
  final String subtitle;
  final Widget Function(BuildContext, VoidCallback onNext) builder;
}

class StepWizard extends StatefulWidget {
  final List<WizardStep> steps;
  final Future<void> Function() onComplete;
  final VoidCallback? onExit;        // back-out from step 0
  final void Function(int step)? onStepChanged;   // draft save hook
  final bool isBusy;
}
```

It owns the header, the progress indicator, the step-info block, the
`PageController`, forward and back movement, and the `mounted` discipline around
`onComplete`. It knows nothing about registration, auth state, or photos.

`RegistrationFlow` becomes: five `WizardStep`s, `onStepChanged: _saveDraft`,
`onComplete: _registerNewAccount`, plus the draft resume prompt. It keeps its
class name and its export, so `welcome_screen.dart` is untouched.
`SocialProfileCompletionFlow` becomes: four `WizardStep`s and
`onComplete: _completeSocialProfile`. It keeps its class name, so `main.dart:92`
is untouched.

Both completion callbacks route their photo work through the same
`PhotoUploader` + `PhotoCompressor` pair, which is what stops the two paths
drifting again.

### Data flow, unchanged

`RegistrationData` stays a mutable bag passed down to each step, and each step
keeps writing its fields on `onNext`. Converting it to an immutable model with a
notifier is a larger change than this scope justifies, and the draft
serialisation is already built around the current shape.

### Error handling

Every auth surface reports through `showAuthSnackBar`. Every backend error
passes through `translateApiError` first — `login_screen.dart:43` already does,
and it becomes the rule rather than the exception. `AuthState.error` remains a
plain string; threading `errorCode` through the provider is noted in
`login_screen.dart:49` as separate work and stays separate.

## The fixes, precisely

1. **Empty password on resume** — `_restoreFrom` clamps its target to `0` when
   the restored `password` is empty. The draft's contents are unchanged; the
   password is still never written to `shared_preferences`.
2. **Dropped gender** — `Gender? gender` added to `UserService.updateProfile`
   and `buildUpdateProfileBody`; `_completeSocialProfile` passes `_data.gender`.
3. **Stranded `profileIncomplete`** — both flows pop on
   `next.isAuthenticated || next.isProfileIncomplete`.
4. **Email regex** — one pattern in `AuthValidators`, three call sites deleted.
5. **`setState` after `await`** — `mounted` guards at all six sites; the
   wizard's completion path handles it once for both flows.
6. **Password bounds** — `AuthValidators.password` enforces 8..128. Login uses
   `requiredField`. The checklist relabels uppercase and number as strength
   hints.
7. **"Log in instead"** (`step_email_password.dart:176`) pushes
   `AppRoutes.login` instead of `Navigator.maybePop()`, which currently drops
   the user at Welcome.

## Deletions

- `lib/screens/auth/registration/steps/step_verify_email.dart`
- `AuthService.verifyEmail`, `AuthService.resendVerificationCode`,
  `AuthService.resetPassword`
- `AuthStatus.registering`, `AuthNotifier.startRegistration()`,
  `AuthNotifier.cancelRegistration()`, and the `AuthStatus.registering` entry in
  `test/providers/realtime_lifecycle_test.dart:44`

## Testing

Test-driven throughout. The 624 passing tests are the regression net; none
should need changing except `realtime_lifecycle_test.dart`, and any test that
does need changing is a signal to re-read the change rather than edit the test.

New coverage:

- `AuthValidators` — unit. Includes `user+tag@gmail.com` and a `.museum` TLD,
  both of which today's regex rejects, plus the 128-character ceiling.
- `PhotoCompressor` — unit, against a generated in-memory image.
- Draft resume clamp — unit. A draft saved at step 3 restores to step 0.
- `StepWizard` — widget, driven by a synthetic two-step list, covering forward,
  back, exit from step 0, and that `onComplete` is not called twice.
- Social completion sends gender — widget or service-level, asserting the
  `updateProfile` body carries the field.
- Both flows pop on `profileIncomplete`.

`flutter analyze` clean, including the `withOpacity` deprecations that
`forgot_password_screen.dart` currently carries.

## Out of scope

- Password self-service as a feature. The endpoints do not exist.
- Translating the new ARB keys into the other eleven locales.
- `go_router`.
- Threading `errorCode` through `AuthState`.
- Making `AuthNotifier` inject its `AuthService` and `BillingService` rather than
  constructing them (`auth_provider.dart:48`). Real, and worth doing — but it
  changes how every auth test builds its subject, which is a wider blast radius
  than this scope wants while the same pass is restructuring the flows.
- Anything outside the auth surface, except `UserService.updateProfile`
  (gender) and `realtime_lifecycle_test.dart` (deleted enum member).
