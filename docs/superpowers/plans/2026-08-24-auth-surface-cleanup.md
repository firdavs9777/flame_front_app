# Auth Surface Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix six functional bugs in the Flame authentication surface and collapse two duplicate registration flows into one shared wizard, without changing any behaviour the 624 passing tests already pin down.

**Architecture:** Bugs first, each behind a failing test, so the fixes are provable while the code is still in its original shape. Structure second: extract four shared units (`AuthValidators`, `showAuthSnackBar`, `AuthGradientScaffold`, `PhotoCompressor`), then a `StepWizard` shell that `RegistrationFlow` and `SocialProfileCompletionFlow` both become thin configs of. Cleanup last: delete the dead surface, rebuild `forgot_password_screen` on the design-system kit, and localise registration.

**Tech Stack:** Flutter, Dart, Riverpod (`flutter_riverpod` `StateNotifierProvider`), `flutter_test`, `flutter_animate`, `shared_preferences`, `image` (compression), ARB-based `gen_l10n`.

**Spec:** `docs/superpowers/specs/2026-08-24-auth-surface-cleanup-design.md`

## Global Constraints

- **Server-authoritative bounds** — copy these exactly from `flame/routes/auth.js:12`; the client must never be stricter or looser: password `min(8).max(128)`, name `min(2).max(50)`, age `18..100`, interests `1..10`, bio `max(500)`, photos `max(9)`.
- **Login is exempt from the password minimum.** Login validates presence only. Raising it to 8 would lock out existing accounts with shorter passwords.
- **The password is never persisted.** `RegistrationDraft` must not gain a `password` key under any circumstances. `test/screens/auth/registration_draft_test.dart` asserts this — never weaken that test.
- **Every new ARB key goes in ALL TWELVE ARB files.** `test/l10n/arb_parity_test.dart` demands an exact key-set match across `app_en` and the eleven others, and it passes at baseline. In the eleven non-English files use the English string verbatim as the placeholder value and no `@key` block — the shape those files already use for untranslated entries (`loginPasswordTooShort` is English today in app_de, app_es, app_fr, app_pt, app_pt_BR and app_ru). Translating them is still a separate content task.
- **Only `app_en.arb` carries `@key` description blocks**, one per key — the existing convention throughout that file.
- **After any ARB edit, regenerate:** `flutter gen-l10n`. **Never commit `lib/l10n/gen/`** — it is gitignored at `.gitignore:48` and `flutter pub get` regenerates it. You still need to run gen-l10n locally to compile and test.
- **Use `withValues(alpha: …)`, never `withOpacity(…)`** — the latter is deprecated and the rest of the codebase has already moved.
- **Snackbars go through the feature helper**, following `lib/screens/chat/widgets/chat_snackbar.dart` and `lib/screens/settings/widgets/settings_snackbar.dart`. No inline `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` in auth after Task 8.
- **Backend errors go through `translateApiError(context.l10n, response)`** from `lib/core/i18n/error_messages.dart` before display.
- **Test command:** `flutter test <path>` for one file, `flutter test` for all. Analyzer: `flutter analyze`.
- **Do not edit a pre-existing test to make a change pass.** The one sanctioned exception is `test/providers/realtime_lifecycle_test.dart` in Task 13, which enumerates an enum member being deleted. If any other existing test fails, the change is wrong.

---

### Task 1: AuthValidators

The single source of truth for auth field validation. Replaces three copies of an email regex that rejects `+` addressing and TLDs longer than four characters, and two disagreeing password minimums.

**Files:**
- Create: `lib/core/validation/auth_validators.dart`
- Modify: `lib/l10n/app_en.arb`
- Test: `test/core/validation/auth_validators_test.dart`

**Interfaces:**
- Consumes: `AppLocalizations` from `lib/l10n/gen/app_localizations.dart`.
- Produces: `class AuthValidators` with `const AuthValidators(AppLocalizations l10n)` and five methods, each returning `String?` (null = valid): `email(String?)`, `password(String?)`, `confirmPassword(String?, {required String against})`, `name(String?)`, `requiredField(String?)`. Also `const kMinPasswordLength = 8`, `kMaxPasswordLength = 128`, `kMinNameLength = 2`, `kMaxNameLength = 50`, and `final RegExp kEmailPattern`.

- [ ] **Step 1: Add the new ARB keys**

Add to `lib/l10n/app_en.arb`, before the closing brace. Keep the existing `loginEmailRequired`, `loginEmailInvalid` and `loginPasswordRequired` keys — the validators reuse them.

```json
  "authPasswordTooShort": "Password must be at least 8 characters",
  "@authPasswordTooShort": {
    "description": "Validation error when a new password is under the server's 8-character minimum"
  },
  "authPasswordTooLong": "Password must be 128 characters or fewer",
  "@authPasswordTooLong": {
    "description": "Validation error when a new password exceeds the server's 128-character ceiling"
  },
  "authConfirmPasswordRequired": "Please confirm your password",
  "@authConfirmPasswordRequired": {
    "description": "Validation error when the confirm-password field is empty"
  },
  "authPasswordsDoNotMatch": "Passwords do not match",
  "@authPasswordsDoNotMatch": {
    "description": "Validation error when confirm-password differs from password"
  },
  "authNameRequired": "Please enter your name",
  "@authNameRequired": {
    "description": "Validation error when the name field is empty"
  },
  "authNameTooShort": "Name must be at least 2 characters",
  "@authNameTooShort": {
    "description": "Validation error when a name is under the server's 2-character minimum"
  },
  "authNameTooLong": "Name must be 50 characters or fewer",
  "@authNameTooLong": {
    "description": "Validation error when a name exceeds the server's 50-character ceiling"
  }
```

Then run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing test**

Create `test/core/validation/auth_validators_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/validation/auth_validators.dart';
import 'package:flame/l10n/gen/app_localizations.dart';

void main() {
  late AuthValidators v;

  setUpAll(() async {
    v = AuthValidators(await AppLocalizations.delegate.load(const Locale('en')));
  });

  group('email', () {
    test('accepts a plain address', () {
      expect(v.email('ada@example.com'), isNull);
    });

    test('accepts plus addressing — the old regex rejected this', () {
      expect(v.email('ada+dating@gmail.com'), isNull);
    });

    test('accepts a TLD longer than four characters', () {
      expect(v.email('ada@science.museum'), isNull);
    });

    test('accepts a subdomain', () {
      expect(v.email('ada@mail.example.co.uk'), isNull);
    });

    test('rejects empty', () {
      expect(v.email(''), isNotNull);
      expect(v.email(null), isNotNull);
    });

    test('rejects an address with no @', () {
      expect(v.email('adaexample.com'), isNotNull);
    });

    test('rejects an address with no domain dot', () {
      expect(v.email('ada@example'), isNotNull);
    });

    test('rejects whitespace inside', () {
      expect(v.email('ada @example.com'), isNotNull);
    });
  });

  group('password', () {
    test('accepts exactly the 8-character minimum', () {
      expect(v.password('abcdefgh'), isNull);
    });

    test('rejects 7 characters', () {
      expect(v.password('abcdefg'), isNotNull);
    });

    test('accepts exactly the 128-character ceiling', () {
      expect(v.password('a' * 128), isNull);
    });

    test('rejects 129 characters — the server 422s on these today', () {
      expect(v.password('a' * 129), isNotNull);
    });

    test('does NOT require an uppercase letter or a digit', () {
      expect(v.password('allcharsnodigits'), isNull);
    });

    test('rejects empty', () {
      expect(v.password(''), isNotNull);
      expect(v.password(null), isNotNull);
    });
  });

  group('confirmPassword', () {
    test('accepts a match', () {
      expect(v.confirmPassword('hunter22', against: 'hunter22'), isNull);
    });

    test('rejects a mismatch', () {
      expect(v.confirmPassword('hunter22', against: 'hunter23'), isNotNull);
    });

    test('rejects empty', () {
      expect(v.confirmPassword('', against: 'hunter22'), isNotNull);
    });
  });

  group('name', () {
    test('accepts a two-character name', () {
      expect(v.name('Jo'), isNull);
    });

    test('rejects one character', () {
      expect(v.name('J'), isNotNull);
    });

    test('accepts exactly 50 characters', () {
      expect(v.name('a' * 50), isNull);
    });

    test('rejects 51 characters', () {
      expect(v.name('a' * 51), isNotNull);
    });

    test('rejects empty', () {
      expect(v.name(''), isNotNull);
    });
  });

  group('requiredField', () {
    test('accepts any non-empty value, however short', () {
      expect(v.requiredField('abc'), isNull);
    });

    test('rejects empty — but imposes no length rule', () {
      expect(v.requiredField(''), isNotNull);
    });
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/core/validation/auth_validators_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:flame/core/validation/auth_validators.dart'`.

- [ ] **Step 4: Write the implementation**

Create `lib/core/validation/auth_validators.dart`:

```dart
import 'package:flame/l10n/gen/app_localizations.dart';

/// Bounds mirrored from the backend's `registerSchema` (`flame/routes/auth.js:12`).
/// The client must not be stricter or looser than the server, or a user is
/// either blocked from a password the server would accept, or sent to a 422
/// with no field-level message.
const int kMinPasswordLength = 8;
const int kMaxPasswordLength = 128;
const int kMinNameLength = 2;
const int kMaxNameLength = 50;

/// HTML5-style address pattern.
///
/// Replaces `^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$`, which was copy-pasted into three
/// screens and rejected two entirely ordinary things: `\w` excludes `+`, so
/// every Gmail user signing up with plus-addressing was turned away, and
/// `{2,4}` rejects `.museum`, `.travel` and `.online`.
final RegExp kEmailPattern = RegExp(
  r"^[\w.!#$%&'*+/=?^`{|}~-]+"
  r'@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
  r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$',
);

/// Field validation for every auth form, in one place.
///
/// Returns `null` when the value is acceptable and a localized message
/// otherwise — the shape `Form`'s `validator:` expects.
class AuthValidators {
  const AuthValidators(this.l10n);

  final AppLocalizations l10n;

  String? email(String? value) {
    if (value == null || value.isEmpty) return l10n.loginEmailRequired;
    if (!kEmailPattern.hasMatch(value)) return l10n.loginEmailInvalid;
    return null;
  }

  /// For a password being CREATED. Login must use [requiredField] instead —
  /// enforcing a minimum at the door would lock out any existing account whose
  /// password predates the current rule.
  String? password(String? value) {
    if (value == null || value.isEmpty) return l10n.loginPasswordRequired;
    if (value.length < kMinPasswordLength) return l10n.authPasswordTooShort;
    if (value.length > kMaxPasswordLength) return l10n.authPasswordTooLong;
    return null;
  }

  String? confirmPassword(String? value, {required String against}) {
    if (value == null || value.isEmpty) return l10n.authConfirmPasswordRequired;
    if (value != against) return l10n.authPasswordsDoNotMatch;
    return null;
  }

  String? name(String? value) {
    if (value == null || value.isEmpty) return l10n.authNameRequired;
    if (value.length < kMinNameLength) return l10n.authNameTooShort;
    if (value.length > kMaxNameLength) return l10n.authNameTooLong;
    return null;
  }

  /// Presence only, no length rule. Login's password field.
  String? requiredField(String? value) {
    if (value == null || value.isEmpty) return l10n.loginPasswordRequired;
    return null;
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/core/validation/auth_validators_test.dart`
Expected: PASS, 22 tests.

- [ ] **Step 6: Commit**

```bash
git add lib/core/validation/auth_validators.dart test/core/validation/auth_validators_test.dart lib/l10n/app_en.arb lib/l10n/gen/
git commit -m "feat(auth): one validator for every auth field

The email regex was copy-pasted into three screens and rejected two ordinary
things: plus addressing, because \\w excludes +, and any TLD over four
characters. Bounds now mirror registerSchema exactly, including the 128-char
ceiling the client never enforced and the server always did."
```

---

### Task 2: Wire the validators into the three forms

Deletes the three regex copies and the disagreeing password minimums. Also demotes the decorative requirements checklist and fixes the "Log in instead" link, both in the same file.

**Files:**
- Modify: `lib/screens/auth/login_screen.dart:209-252`
- Modify: `lib/screens/auth/registration/steps/step_email_password.dart:124-235`, `:237-285`, `:170-193`
- Modify: `lib/screens/auth/registration/steps/step_profile_info.dart:115-132`
- Modify: `lib/core/navigation/app_routes.dart`, `lib/core/navigation/app_router.dart`
- Modify: `lib/l10n/app_en.arb`
- Test: `test/screens/auth/login_hidden_features_test.dart` (existing, must keep passing), `test/core/navigation/` router test (existing, must keep passing)

**Interfaces:**
- Consumes: `AuthValidators`, `kMinPasswordLength` from Task 1.
- Produces: `AppRoutes.login = '/auth/login'`, resolving to `const LoginScreen()`.

- [ ] **Step 1: Add the login route**

`AppRoutes.login` does not exist — `LoginScreen` is only reachable through a `Navigator.push` closure in `welcome_screen.dart:226`. Step 5 needs a name to push.

In `lib/core/navigation/app_routes.dart`, beside `forgotPassword`:

```dart
  static const login = '/auth/login';
  static const forgotPassword = '/auth/forgot-password';
```

and add `login,` to the `all` list immediately before `forgotPassword,`.

In `lib/core/navigation/app_router.dart`, add an import for `package:flame/screens/auth/login_screen.dart` and a case beside the `forgotPassword` one:

```dart
      case AppRoutes.login:
        return _page(settings, const LoginScreen());
```

- [ ] **Step 2: Run the router test to verify the new name resolves**

Run: `flutter test test/core/navigation/`
Expected: PASS. The router test asserts every name in `AppRoutes.all` resolves to something other than `RouteNotFoundScreen`; a missing case fails it.

- [ ] **Step 3: Add the strength-hint ARB keys**

The checklist currently presents "one uppercase letter" and "one number" as requirements. No validator and no server schema enforces either. Relabel them as hints.

```json
  "registerPasswordHintsTitle": "Make it stronger:",
  "@registerPasswordHintsTitle": {
    "description": "Heading above optional password strength hints — these are suggestions, not requirements"
  },
  "registerPasswordHintLength": "At least 8 characters",
  "@registerPasswordHintLength": {
    "description": "Password strength hint: minimum length. This one IS enforced."
  },
  "registerPasswordHintUppercase": "One uppercase letter",
  "@registerPasswordHintUppercase": {
    "description": "Password strength hint: an uppercase letter. Advisory only."
  },
  "registerPasswordHintNumber": "One number",
  "@registerPasswordHintNumber": {
    "description": "Password strength hint: a digit. Advisory only."
  },
  "registerEmailTaken": "That email is already registered",
  "@registerEmailTaken": {
    "description": "Inline error when the availability check reports the address is in use"
  },
  "registerLogInInstead": "Log in instead",
  "@registerLogInInstead": {
    "description": "Link offered beside the email-taken error, sending the user to the login screen"
  }
```

Run `flutter gen-l10n`.

- [ ] **Step 4: Replace login's validators**

In `lib/screens/auth/login_screen.dart`, add `import 'package:flame/core/validation/auth_validators.dart';` and replace `_buildEmailField` and `_buildPasswordField` in full:

```dart
  Widget _buildEmailField() {
    final validators = AuthValidators(context.l10n);
    return AppInput(
      controller: _emailController,
      label: context.l10n.loginEmailLabel,
      hint: context.l10n.loginEmailHint,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      prefixIcon: Icons.email_outlined,
      validator: validators.email,
    );
  }

  Widget _buildPasswordField() {
    final validators = AuthValidators(context.l10n);
    return AppInput(
      controller: _passwordController,
      label: context.l10n.loginPasswordLabel,
      hint: context.l10n.loginPasswordHint,
      obscureText: true,
      textInputAction: TextInputAction.done,
      prefixIcon: Icons.lock_outline_rounded,
      onSubmitted: (_) => _handleLogin(),
      // Presence only. A minimum here would lock out any existing account
      // whose password is shorter than today's registration rule.
      validator: validators.requiredField,
    );
  }
```

`loginPasswordTooShort` becomes unused. **Leave it in the ARBs.** Removing it from the template would leave the key present in eleven locale files that the Global Constraints forbid touching, and `gen_l10n` would then warn on every build. An unused key costs nothing.

- [ ] **Step 5: Replace step_email_password's validators, checklist and link**

In `lib/screens/auth/registration/steps/step_email_password.dart`, add `import 'package:flame/core/validation/auth_validators.dart';` and `import 'package:flame/core/navigation/app_routes.dart';`.

Replace the three field builders:

```dart
  Widget _buildEmailField() {
    final validators = AuthValidators(context.l10n);
    return AppInput(
      controller: _emailController,
      label: 'Email Address',
      hint: 'you@example.com',
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      prefixIcon: Icons.email_outlined,
      onChanged: (_) {
        if (_emailAvailabilityError != null) {
          setState(() => _emailAvailabilityError = null);
        }
      },
      validator: validators.email,
    );
  }

  Widget _buildPasswordField() {
    final validators = AuthValidators(context.l10n);
    return AppInput(
      controller: _passwordController,
      label: 'Password',
      hint: 'Create a strong password',
      obscureText: true,
      textInputAction: TextInputAction.next,
      prefixIcon: Icons.lock_outline_rounded,
      onChanged: (_) => setState(() {}), // live-update the strength hints
      validator: validators.password,
    );
  }

  Widget _buildConfirmPasswordField() {
    final validators = AuthValidators(context.l10n);
    return AppInput(
      controller: _confirmPasswordController,
      label: 'Confirm Password',
      hint: 'Confirm your password',
      obscureText: true,
      textInputAction: TextInputAction.done,
      prefixIcon: Icons.lock_outline_rounded,
      validator: (value) => validators.confirmPassword(
        value,
        against: _passwordController.text,
      ),
    );
  }
```

Replace `_buildPasswordRequirements` (the heading and the length row now tell the truth; uppercase and number are labelled as what they are):

```dart
  Widget _buildPasswordRequirements() {
    final password = _passwordController.text;
    final hasLength = password.length >= kMinPasswordLength;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: AppRadius.borderMD,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.registerPasswordHintsTitle,
            style: AppTypography.labelMedium.copyWith(color: AppColors.gray600),
          ),
          const SizedBox(height: 8),
          _buildRequirement(context.l10n.registerPasswordHintLength, hasLength),
          _buildRequirement(context.l10n.registerPasswordHintUppercase, hasUppercase),
          _buildRequirement(context.l10n.registerPasswordHintNumber, hasNumber),
        ],
      ),
    );
  }
```

In `_buildEmailAvailabilityError`, replace the `TextButton`'s `onPressed` and label. `maybePop()` drops the user at Welcome, not Login — the flow was pushed from there:

```dart
            child: TextButton(
              onPressed: () => Navigator.of(context)
                  .pushReplacementNamed(AppRoutes.login),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppTheme.primaryColor,
              ),
              child: Text(
                context.l10n.registerLogInInstead,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
```

And in `_handleContinue`, replace the hardcoded string:

```dart
        setState(() {
          _emailAvailabilityError = context.l10n.registerEmailTaken;
        });
```

- [ ] **Step 6: Replace step_profile_info's name validator**

In `lib/screens/auth/registration/steps/step_profile_info.dart`, add the imports `package:flame/core/validation/auth_validators.dart` and `package:flame/core/i18n/build_context_ext.dart`, then:

```dart
  Widget _buildNameField() {
    final validators = AuthValidators(context.l10n);
    return AppInput(
      controller: _nameController,
      label: 'First Name',
      hint: 'Your first name',
      prefixIcon: Icons.person_outline_rounded,
      textInputAction: TextInputAction.next,
      validator: validators.name,
    );
  }
```

This adds the 50-character ceiling the server enforces and the client did not.

- [ ] **Step 7: Verify no regex copies remain**

Run: `grep -rn 'w-..]+@' lib/`
Expected: no output.

- [ ] **Step 8: Run the affected tests**

Run: `flutter test test/screens/auth/ test/core/`
Expected: PASS. `step_email_password_test.dart` enters `Password1` — 9 characters, still valid under the 8-character rule.

- [ ] **Step 9: Commit**

```bash
git add lib/screens/auth/ lib/core/navigation/ lib/l10n/
git commit -m "fix(auth): one validation rule per field, and stop the checklist lying

Login drops its 6-character minimum rather than being raised to 8 — raising it
would lock out existing accounts. The registration checklist stops presenting
uppercase and number as requirements no validator or schema enforces, and the
128-character ceiling the server has always had is now enforced client-side.

'Log in instead' pushed maybePop(), which drops the user at Welcome. There was
no named login route to push, so there is one now."
```

---

### Task 3: Gender reaches the server on social sign-up

`StepProfileInfo` collects gender and `SocialProfileCompletionFlow` throws it away, because `updateProfile` has no parameter for it. The backend grew support in `378aa8f`.

**Files:**
- Modify: `lib/services/user_service.dart:7-24` (`buildUpdateProfileBody`), `:54-67` (`updateProfile`)
- Modify: `lib/screens/auth/registration/social_profile_completion_flow.dart:211-217`
- Test: `test/services/update_profile_body_test.dart`

**Interfaces:**
- Produces: `buildUpdateProfileBody({..., Gender? gender})` and `UserService.updateProfile({..., Gender? gender})`. Task 12 calls the latter with `gender:`.

- [ ] **Step 1: Write the failing test**

Append inside the existing `group('buildUpdateProfileBody', ...)` in `test/services/update_profile_body_test.dart`:

```dart
    test('writes gender in camelCase when given', () {
      final body = buildUpdateProfileBody(gender: Gender.female);
      expect(body['gender'], 'female');
    });

    test('also includes snake_case gender, matching lookingFor', () {
      final body = buildUpdateProfileBody(gender: Gender.male);
      expect(body['gender'], 'male');
    });

    test('omits gender when null — a profile edit must not reset it', () {
      final body = buildUpdateProfileBody(name: 'Ann');
      expect(body.containsKey('gender'), isFalse);
    });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/services/update_profile_body_test.dart`
Expected: FAIL — `No named parameter with the name 'gender'`.

- [ ] **Step 3: Add the parameter**

In `lib/services/user_service.dart`, `buildUpdateProfileBody`:

```dart
Map<String, dynamic> buildUpdateProfileBody({
  String? name,
  String? bio,
  List<String>? interests,
  Gender? lookingFor,
  Gender? gender,
  int? age,
}) {
  final body = <String, dynamic>{};
  if (name != null) body['name'] = name;
  if (bio != null) body['bio'] = bio;
  if (interests != null) body['interests'] = interests;
  if (lookingFor != null) {
    body['lookingFor'] = lookingFor.toApiString();
    body['looking_for'] = lookingFor.toApiString();
  }
  if (gender != null) body['gender'] = gender.toApiString();
  if (age != null) body['age'] = age;
  return body;
}
```

`gender` needs no snake_case twin — the backend's PATCH schema names it `gender` in both conventions.

Then thread it through `updateProfile`:

```dart
  Future<ServiceResult<User>> updateProfile({
    String? name,
    String? bio,
    List<String>? interests,
    Gender? lookingFor,
    Gender? gender,
    int? age,
  }) async {
    final body = buildUpdateProfileBody(
      name: name,
      bio: bio,
      interests: interests,
      lookingFor: lookingFor,
      gender: gender,
      age: age,
    );
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/services/update_profile_body_test.dart`
Expected: PASS.

- [ ] **Step 5: Pass gender at the call site**

In `lib/screens/auth/registration/social_profile_completion_flow.dart`, `_handleComplete`:

```dart
      final profileResult = await userService.updateProfile(
        name: _data.name,
        bio: _data.bio,
        interests: _data.interests,
        lookingFor: _data.lookingFor,
        gender: _data.gender,
        age: _data.age,
      );
```

- [ ] **Step 6: Run the full suite**

Run: `flutter test`
Expected: PASS, no new failures.

- [ ] **Step 7: Commit**

```bash
git add lib/services/user_service.dart lib/screens/auth/registration/social_profile_completion_flow.dart test/services/update_profile_body_test.dart
git commit -m "fix(auth): social sign-up stops discarding gender

StepProfileInfo collected it, updateProfile had no parameter for it, so every
Google signup kept whatever the server defaulted them to. The backend accepted
the field as of 378aa8f — the client never caught up."
```

---

### Task 4: A resumed draft cannot submit an empty password

`RegistrationDraft` correctly refuses to persist the password. `_restoreFrom` then jumps the user past the only step that collects one.

**Files:**
- Modify: `lib/screens/auth/registration/registration_flow.dart:118-136`
- Test: `test/screens/auth/registration_resume_test.dart` (create)

**Interfaces:**
- Produces: `int resumeStepFor({required String password, required int savedStep, required int totalSteps})` — a top-level function in `registration_flow.dart`, testable without a widget tree, mirroring how `canContinue` is exposed from `step_bio_interests.dart`.

- [ ] **Step 1: Write the failing test**

Create `test/screens/auth/registration_resume_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';

void main() {
  group('resumeStepFor', () {
    test('a draft with no password restores to step 0, whatever it saved', () {
      // The password is deliberately never persisted. Landing the user past
      // step 0 means register() posts '' and the server 422s on min(8) with
      // nothing on screen to explain it.
      expect(
        resumeStepFor(password: '', savedStep: 3, totalSteps: 5),
        0,
      );
    });

    test('a draft with a password honours its saved step', () {
      expect(
        resumeStepFor(password: 'hunter22', savedStep: 3, totalSteps: 5),
        3,
      );
    });

    test('clamps a saved step past the end of the flow', () {
      expect(
        resumeStepFor(password: 'hunter22', savedStep: 99, totalSteps: 5),
        4,
      );
    });

    test('clamps a negative saved step', () {
      expect(
        resumeStepFor(password: 'hunter22', savedStep: -2, totalSteps: 5),
        0,
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/screens/auth/registration_resume_test.dart`
Expected: FAIL — `Undefined name 'resumeStepFor'`.

- [ ] **Step 3: Write the implementation**

Add at the bottom of `lib/screens/auth/registration/registration_flow.dart`, outside the class:

```dart
/// Which step a resumed draft should open on.
///
/// The password is deliberately never persisted (see [RegistrationDraft]), and
/// step 0 is the only place one is entered. Resuming past it left `_data.password`
/// empty all the way into `register()`, which the server rejects with a 422 the
/// user cannot see or escape. So a draft without a password restarts at step 0 —
/// everything else the user already typed is still restored.
///
/// Extracted so the rule is unit-testable independent of the widget.
int resumeStepFor({
  required String password,
  required int savedStep,
  required int totalSteps,
}) {
  if (password.isEmpty) return 0;
  return savedStep.clamp(0, totalSteps - 1);
}
```

And use it in `_restoreFrom`, replacing the `final target = step.clamp(...)` line:

```dart
  void _restoreFrom(RegistrationData data, int step) {
    _data
      ..email = data.email
      ..name = data.name
      ..age = data.age
      ..gender = data.gender
      ..lookingFor = data.lookingFor
      ..bio = data.bio
      ..interests = data.interests
      ..photoFiles = data.photoFiles
      ..latitude = data.latitude
      ..longitude = data.longitude;

    final target = resumeStepFor(
      password: _data.password,
      savedStep: step,
      totalSteps: _totalSteps,
    );
    setState(() => _currentStep = target);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(target);
    }
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/screens/auth/registration_resume_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Confirm the draft still refuses to store the password**

Run: `flutter test test/screens/auth/registration_draft_test.dart`
Expected: PASS. The "password is NEVER persisted" test must still pass — the fix works around the missing password, it does not start saving one.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/auth/registration/registration_flow.dart test/screens/auth/registration_resume_test.dart
git commit -m "fix(auth): a resumed draft can no longer submit an empty password

The draft is right not to persist the password. _restoreFrom was wrong to jump
past the only step that collects one — resume at step 2 or later and register()
posted '', which registerSchema rejects with a 422 the user cannot diagnose.
The password still never touches disk."
```

---

### Task 5: Both flows release the screen for a profileIncomplete user

**Files:**
- Modify: `lib/screens/auth/login_screen.dart:38-41`
- Modify: `lib/screens/auth/registration/registration_flow.dart:147-151`
- Test: `test/screens/auth/auth_navigation_test.dart` (create)

**Interfaces:**
- Consumes: `AuthState.isProfileIncomplete` (already exists, `auth_provider.dart:44`).

- [ ] **Step 1: Write the failing test**

Create `test/screens/auth/auth_navigation_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/screens/auth/login_screen.dart';

/// A notifier whose state the test drives directly.
class _StubAuthNotifier extends AuthNotifier {
  void emit(AuthState next) => state = next;
}

void main() {
  testWidgets('login pops itself when the user lands on profileIncomplete',
      (tester) async {
    final notifier = _StubAuthNotifier();
    addTearDown(notifier.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: kSupportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                child: const Text('open login'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open login'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    // A social login that needs profile completion. main.dart swaps `home:`
    // underneath; the pushed login screen has to get out of the way or it sits
    // on top of the completion flow forever.
    notifier.emit(const AuthState(status: AuthStatus.profileIncomplete));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/screens/auth/auth_navigation_test.dart`
Expected: FAIL — `Expected: no matching candidates / Actual: exactly one widget`. The login screen is still on top.

- [ ] **Step 3: Widen both listeners**

In `lib/screens/auth/login_screen.dart`:

```dart
    ref.listen<AuthState>(authProvider, (previous, next) {
      // Both terminal states mean this pushed route has to get out of the way:
      // main.dart's `home:` has already swapped to MainShell or to the profile
      // completion flow underneath it.
      if (next.isAuthenticated || next.isProfileIncomplete) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
```

In `lib/screens/auth/registration/registration_flow.dart`:

```dart
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (_registrationComplete &&
          (next.isAuthenticated || next.isProfileIncomplete)) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/screens/auth/auth_navigation_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the whole auth suite**

Run: `flutter test test/screens/auth/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/auth/login_screen.dart lib/screens/auth/registration/registration_flow.dart test/screens/auth/auth_navigation_test.dart
git commit -m "fix(auth): a profileIncomplete user is no longer stranded on login

LoginScreen is pushed over home:. Its listener popped only on isAuthenticated,
so a social login needing profile completion swapped home: underneath while the
login screen stayed on top of it."
```

---

### Task 6: mounted guards on every post-await setState

**Files:**
- Modify: `lib/screens/auth/registration/registration_flow.dart:359-437`
- Modify: `lib/screens/auth/registration/social_profile_completion_flow.dart:204-255`

**Interfaces:** none new.

- [ ] **Step 1: Guard registration_flow**

Photo upload and registration are the longest operations in the app and the easiest to back out of. Replace `_handlePhotosComplete` in full:

```dart
  Future<void> _handlePhotosComplete() async {
    setState(() => _isUploading = true);

    try {
      final locationService = LocationService();
      final locationResult = await locationService.getCurrentPosition();
      if (!mounted) return;

      if (!locationResult.success) {
        setState(() => _isUploading = false);
        _showLocationError(locationResult.error ?? 'Failed to get location');
        return;
      }

      _data.latitude = locationResult.latitude;
      _data.longitude = locationResult.longitude;

      final photoUrls = await _uploadPhotosForRegistration();
      if (!mounted) return;

      if (photoUrls.isEmpty) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to upload photos. Please try again.'),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        return;
      }

      final success = await ref.read(authProvider.notifier).register(
            email: _data.email,
            password: _data.password,
            name: _data.name,
            age: _data.age,
            gender: _data.gender,
            lookingFor: _data.lookingFor,
            bio: _data.bio,
            interests: _data.interests,
            photos: photoUrls,
            latitude: _data.latitude!,
            longitude: _data.longitude!,
          );
      if (!mounted) return;

      setState(() => _isUploading = false);

      if (success) {
        // Tokens are already issued. The ref.listen above pops to root once
        // auth state flips. Drop the draft so a future signup starts clean.
        await _draft.clear();
        if (!mounted) return;
        setState(() => _registrationComplete = true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }
```

Those inline SnackBars are replaced wholesale in Task 8 — leave them for now so this task stays one concern.

- [ ] **Step 2: Guard social_profile_completion_flow**

Replace `_handleComplete` in full. Note the success path also resets `_isUploading`, which it never did:

```dart
  Future<void> _handleComplete() async {
    setState(() => _isUploading = true);

    try {
      final userService = UserService();

      final profileResult = await userService.updateProfile(
        name: _data.name,
        bio: _data.bio,
        interests: _data.interests,
        lookingFor: _data.lookingFor,
        gender: _data.gender,
        age: _data.age,
      );
      if (!mounted) return;

      if (!profileResult.success) {
        setState(() => _isUploading = false);
        _showError(profileResult.error ?? 'Failed to update profile');
        return;
      }

      String tempPath;
      try {
        final dir = await Directory.systemTemp.createTemp('flame_photos');
        tempPath = dir.path;
      } catch (_) {
        tempPath = Directory.systemTemp.path;
      }

      for (int i = 0; i < _data.photoFiles.length; i++) {
        final file = _data.photoFiles[i];
        final isPrimary = i == 0;
        try {
          final compressed = await _compressImage(file, tempPath, i);
          await userService.uploadPhoto(compressed, isPrimary: isPrimary);
        } catch (e) {
          debugPrint('Photo upload error: $e');
        }
      }
      if (!mounted) return;

      final userResult = await userService.getCurrentUser();
      if (!mounted) return;
      if (userResult.success && userResult.data != null) {
        ref.read(authProvider.notifier).updateUser(userResult.data!);
      }
      setState(() => _isUploading = false);
      ref.read(authProvider.notifier).markAuthenticated();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      _showError('Error: ${e.toString()}');
    }
  }
```

- [ ] **Step 3: Verify no unguarded post-await setState remains**

Run: `flutter analyze lib/screens/auth/`
Expected: no `use_build_context_synchronously` findings in either file.

- [ ] **Step 4: Run the suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/auth/registration/
git commit -m "fix(auth): guard every setState that runs after an await

Six sites across the two flows. Photo upload and registration are the longest
operations in the app and the easiest to back out of. The social flow also
never reset _isUploading on its success path."
```

---

### Task 7: Extract PhotoCompressor

The 800px / JPEG-70 routine exists twice, near-identically, as a private method in each flow.

**Files:**
- Create: `lib/core/image/photo_compressor.dart`
- Modify: `lib/screens/auth/registration/registration_flow.dart:488-525` (delete `_compressImage`)
- Modify: `lib/screens/auth/registration/social_profile_completion_flow.dart:257-277` (delete `_compressImage`)
- Test: `test/core/image/photo_compressor_test.dart`

**Interfaces:**
- Produces: `class PhotoCompressor` with `const PhotoCompressor()` and `Future<File> compress(File source, {required String tempDir, required int index})`. Constants `kMaxPhotoDimension = 800`, `kPhotoJpegQuality = 70`.

- [ ] **Step 1: Write the failing test**

Create `test/core/image/photo_compressor_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:flame/core/image/photo_compressor.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('compressor_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Writes a solid-colour PNG of the given size and returns the file.
  Future<File> makeImage(int width, int height, String name) async {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(120, 80, 200));
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(img.encodePng(image));
    return file;
  }

  test('a landscape image over 800px is resized by width', () async {
    final source = await makeImage(1600, 900, 'wide.png');

    final out = await const PhotoCompressor()
        .compress(source, tempDir: tempDir.path, index: 0);

    final decoded = img.decodeImage(await out.readAsBytes())!;
    expect(decoded.width, kMaxPhotoDimension);
    expect(decoded.height, lessThan(kMaxPhotoDimension));
  });

  test('a portrait image over 800px is resized by height', () async {
    final source = await makeImage(900, 1600, 'tall.png');

    final out = await const PhotoCompressor()
        .compress(source, tempDir: tempDir.path, index: 1);

    final decoded = img.decodeImage(await out.readAsBytes())!;
    expect(decoded.height, kMaxPhotoDimension);
    expect(decoded.width, lessThan(kMaxPhotoDimension));
  });

  test('an image already under the cap keeps its dimensions', () async {
    final source = await makeImage(400, 300, 'small.png');

    final out = await const PhotoCompressor()
        .compress(source, tempDir: tempDir.path, index: 2);

    final decoded = img.decodeImage(await out.readAsBytes())!;
    expect(decoded.width, 400);
    expect(decoded.height, 300);
  });

  test('the output is written to an index-stable path inside tempDir', () async {
    final source = await makeImage(100, 100, 'x.png');

    final out = await const PhotoCompressor()
        .compress(source, tempDir: tempDir.path, index: 3);

    expect(out.path, '${tempDir.path}/compressed_3.jpg');
  });

  test('undecodable bytes fall back to the original file', () async {
    final broken = File('${tempDir.path}/broken.jpg');
    await broken.writeAsBytes([0, 1, 2, 3, 4]);

    final out = await const PhotoCompressor()
        .compress(broken, tempDir: tempDir.path, index: 4);

    expect(out.path, broken.path);
  });

  test('an unwritable tempDir falls back to the original rather than throwing',
      () async {
    final source = await makeImage(100, 100, 'y.png');

    final out = await const PhotoCompressor()
        .compress(source, tempDir: '/no/such/directory', index: 5);

    expect(out.path, source.path);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/core/image/photo_compressor_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/image/photo_compressor.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Longest edge, in pixels, a registration photo is reduced to.
const int kMaxPhotoDimension = 800;

/// JPEG quality for the re-encode.
const int kPhotoJpegQuality = 70;

/// Shrinks and re-encodes a photo before upload.
///
/// Lifted out of `RegistrationFlow` and `SocialProfileCompletionFlow`, which
/// each carried a near-identical private copy — the kind of duplication that let
/// their upload paths drift apart in the first place.
///
/// Every failure path returns the ORIGINAL file rather than throwing: a photo
/// that uploads at full size is a slow signup, while a thrown exception is a
/// failed one.
class PhotoCompressor {
  const PhotoCompressor();

  /// Compresses [source] into `<tempDir>/compressed_<index>.jpg`.
  ///
  /// [index] keeps output paths stable and collision-free when several photos
  /// are compressed concurrently.
  Future<File> compress(
    File source, {
    required String tempDir,
    required int index,
  }) async {
    try {
      final bytes = await source.readAsBytes();

      img.Image? image = img.decodeImage(bytes);
      if (image == null) {
        debugPrint('PhotoCompressor: could not decode photo $index, using original');
        return source;
      }

      if (image.width > kMaxPhotoDimension || image.height > kMaxPhotoDimension) {
        image = image.width > image.height
            ? img.copyResize(image, width: kMaxPhotoDimension)
            : img.copyResize(image, height: kMaxPhotoDimension);
      }

      final encoded = img.encodeJpg(image, quality: kPhotoJpegQuality);
      final out = File('$tempDir/compressed_$index.jpg');
      await out.writeAsBytes(encoded);

      debugPrint(
        'PhotoCompressor: photo $index '
        '${(bytes.length / 1024).toStringAsFixed(0)} KB -> '
        '${(encoded.length / 1024).toStringAsFixed(0)} KB',
      );
      return out;
    } catch (e) {
      debugPrint('PhotoCompressor: $e, using original');
      return source;
    }
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/core/image/photo_compressor_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Use it in both flows**

In `lib/screens/auth/registration/registration_flow.dart`: delete the private `_compressImage` method entirely, drop the now-unused `import 'package:image/image.dart' as img;`, add `import 'package:flame/core/image/photo_compressor.dart';`, and in `_uploadPhotosForRegistration` replace the compression call:

```dart
          final compressedFile = await const PhotoCompressor()
              .compress(file, tempDir: tempPath, index: i);
```

In `lib/screens/auth/registration/social_profile_completion_flow.dart`: delete `_compressImage`, drop the `img` import, add the `PhotoCompressor` import, and replace the call inside the upload loop:

```dart
          final compressed = await const PhotoCompressor()
              .compress(file, tempDir: tempPath, index: i);
```

- [ ] **Step 6: Run the suite**

Run: `flutter test && flutter analyze lib/`
Expected: PASS, no unused-import warnings.

- [ ] **Step 7: Commit**

```bash
git add lib/core/image/photo_compressor.dart test/core/image/photo_compressor_test.dart lib/screens/auth/registration/
git commit -m "refactor(auth): one photo compressor, not two copies

Both flows carried a near-identical private _compressImage. Every failure path
returns the original file rather than throwing — a slow signup beats a failed
one — and that is now tested rather than assumed."
```

---

### Task 8: showAuthSnackBar

Fourteen hand-rolled SnackBars share one decoration. The codebase already settled this pattern twice.

**Files:**
- Create: `lib/screens/auth/widgets/auth_snackbar.dart`
- Modify: `lib/screens/auth/login_screen.dart`, `forgot_password_screen.dart`, `registration/registration_flow.dart`, `registration/social_profile_completion_flow.dart`, `registration/steps/step_profile_info.dart`, `registration/steps/step_looking_for.dart`, `registration/steps/step_bio_interests.dart`, `registration/steps/step_photos.dart`
- Test: `test/screens/auth/auth_snackbar_test.dart`

**Interfaces:**
- Produces: `enum AuthSnackBarType { info, error, warning }` and `void showAuthSnackBar(BuildContext context, {required String message, AuthSnackBarType type = AuthSnackBarType.info})`.

- [ ] **Step 1: Write the failing test**

Create `test/screens/auth/auth_snackbar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/screens/auth/widgets/auth_snackbar.dart';

void main() {
  Future<void> pumpAndShow(
    WidgetTester tester,
    AuthSnackBarType type,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () =>
                  showAuthSnackBar(context, message: 'hello', type: type),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
  }

  testWidgets('shows the message', (tester) async {
    await pumpAndShow(tester, AuthSnackBarType.info);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('error uses the theme error colour', (tester) async {
    await pumpAndShow(tester, AuthSnackBarType.error);
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, AppTheme.errorColor);
  });

  testWidgets('info leaves the background to the theme', (tester) async {
    await pumpAndShow(tester, AuthSnackBarType.info);
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, isNull);
  });

  testWidgets('an unmounted context is a no-op, not a crash', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(
      () => showAuthSnackBar(captured, message: 'gone'),
      returnsNormally,
    );
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/screens/auth/auth_snackbar_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Write the implementation**

Create `lib/screens/auth/widgets/auth_snackbar.dart`, mirroring `chat_snackbar.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:flame/theme/app_theme.dart';

enum AuthSnackBarType { info, error, warning }

/// One place the auth surface reports a transient outcome.
///
/// Replaces fourteen inline SnackBars that each re-declared the same error
/// colour, floating behaviour and 12px radius. Mirrors chat_snackbar and
/// settings_snackbar, including their `context.mounted` guard — a handler can
/// report an outcome without first proving its widget is still alive.
void showAuthSnackBar(
  BuildContext context, {
  required String message,
  AuthSnackBarType type = AuthSnackBarType.info,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: switch (type) {
        AuthSnackBarType.error => AppTheme.errorColor,
        // AppColors.warning is 0xFFFF9800 — the orange step_bio_interests
        // already reaches for as a literal `Colors.orange`.
        AuthSnackBarType.warning => AppColors.warning,
        AuthSnackBarType.info => null,
      },
    ),
  );
}
```

`AppTheme` exposes `errorColor` and `successColor` but no warning; `AppColors.warning` is the token, and both come from `lib/theme/app_theme.dart`, so the single import covers them.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/screens/auth/auth_snackbar_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Replace every inline SnackBar in the auth surface**

Work through each site, replacing the whole `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` expression with one call. Examples of each shape:

`login_screen.dart` — the error listener:
```dart
        showAuthSnackBar(context, message: message, type: AuthSnackBarType.error);
```

`step_bio_interests.dart:213` — the interest cap:
```dart
        showAuthSnackBar(
          context,
          message: 'Maximum 5 interests allowed',
          type: AuthSnackBarType.warning,
        );
```

`social_profile_completion_flow.dart` — delete the private `_showError` method entirely and replace its call sites with `showAuthSnackBar(context, message: …, type: AuthSnackBarType.error)`.

Do the same in `step_photos.dart` (`_showError`), `step_profile_info.dart`, `step_looking_for.dart`, `registration_flow.dart` (both sites from Task 6) and `forgot_password_screen.dart`.

- [ ] **Step 6: Verify none are left**

Run: `grep -rn "showSnackBar" lib/screens/auth/ lib/widgets/auth/ | grep -v auth_snackbar.dart`
Expected: no output.

- [ ] **Step 7: Run the suite**

Run: `flutter test`
Expected: PASS. If a widget test asserted on SnackBar styling it may need its finder adjusted — check whether the test was asserting behaviour or decoration before touching it.

- [ ] **Step 8: Commit**

```bash
git add lib/screens/auth/ test/screens/auth/auth_snackbar_test.dart
git commit -m "refactor(auth): one snackbar helper, following chat and settings

Fourteen inline SnackBars each re-declared the same error colour, floating
behaviour and radius. Same shape the chat and settings surfaces already use,
mounted guard included."
```

---

### Task 9: AuthGradientScaffold

The `FF6B6B → FF8E53` gradient, `SafeArea` and translucent back button are copied into four screens.

**Files:**
- Create: `lib/screens/auth/widgets/auth_gradient_scaffold.dart`
- Modify: `lib/screens/auth/login_screen.dart:66-143`
- Test: `test/screens/auth/auth_gradient_scaffold_test.dart`

**Interfaces:**
- Produces: `class AuthGradientScaffold extends StatelessWidget` with `const AuthGradientScaffold({required Widget child, VoidCallback? onBack, bool scrollable = true})`, and `const kAuthGradient = LinearGradient(...)`.
- Consumed by: Task 10 (`StepWizard`, with `scrollable: false`) and Task 14 (`forgot_password_screen`).

- [ ] **Step 1: Write the failing test**

Create `test/screens/auth/auth_gradient_scaffold_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/screens/auth/widgets/auth_gradient_scaffold.dart';

void main() {
  testWidgets('renders its child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGradientScaffold(child: Text('body')),
      ),
    );
    expect(find.text('body'), findsOneWidget);
  });

  testWidgets('shows no back button when onBack is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGradientScaffold(child: Text('body')),
      ),
    );
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
  });

  testWidgets('a back button invokes onBack', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGradientScaffold(
          onBack: () => tapped = true,
          child: const Text('body'),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    expect(tapped, isTrue);
  });

  testWidgets('scrollable: false omits the scroll view', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AuthGradientScaffold(scrollable: false, child: Text('body')),
      ),
    );
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('body'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/screens/auth/auth_gradient_scaffold_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Write the implementation**

Create `lib/screens/auth/widgets/auth_gradient_scaffold.dart`:

```dart
import 'package:flutter/material.dart';

/// The warm gradient every unauthenticated screen sits on.
///
/// Declared once because four screens each carried their own copy of these two
/// stops, and a fifth would have made five.
const LinearGradient kAuthGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
);

/// Gradient background, SafeArea, and the translucent rounded back button
/// shared by login, forgot-password and both registration flows.
///
/// [onBack] null means no back affordance at all — the button is not merely
/// disabled, it is absent, so nothing occupies the corner.
///
/// [scrollable] wraps the child in a [SingleChildScrollView]. The wizard passes
/// false: it owns an [Expanded] PageView, which cannot live inside an
/// unbounded scroll view.
class AuthGradientScaffold extends StatelessWidget {
  const AuthGradientScaffold({
    super.key,
    required this.child,
    this.onBack,
    this.scrollable = true,
  });

  final Widget child;
  final VoidCallback? onBack;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null) ...[
          const SizedBox(height: 16),
          _BackButton(onPressed: onBack!),
        ],
        if (scrollable) child else Expanded(child: child),
      ],
    );

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: kAuthGradient),
        child: SafeArea(
          child: scrollable
              ? SingleChildScrollView(child: content)
              : content,
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}
```

Note: `scrollable: true` puts `child` directly in a `Column` inside a `SingleChildScrollView`, so callers keep supplying their own horizontal padding — which `login_screen` already does.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/screens/auth/auth_gradient_scaffold_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Adopt it in login_screen**

In `lib/screens/auth/login_screen.dart`, delete `_buildBackButton()` and replace the `return Scaffold(...)` in `build` with:

```dart
    return AuthGradientScaffold(
      onBack: () => Navigator.of(context).pop(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            _buildHeader()
                .animate()
                .fadeIn(delay: 100.ms, duration: 500.ms)
                .slideX(begin: -0.1, end: 0, delay: 100.ms, duration: 500.ms),
            const SizedBox(height: 48),
            _buildLoginCard(authState)
                .animate()
                .fadeIn(delay: 200.ms, duration: 600.ms)
                .slideY(begin: 0.1, end: 0, delay: 200.ms, duration: 600.ms),
            const SizedBox(height: 32),
            const SocialSignInButtons()
                .animate()
                .fadeIn(delay: 400.ms, duration: 600.ms),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
```

Add the import and drop any now-unused ones.

- [ ] **Step 6: Run the suite**

Run: `flutter test test/screens/auth/ && flutter analyze lib/screens/auth/`
Expected: PASS, clean.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/auth/widgets/auth_gradient_scaffold.dart test/screens/auth/auth_gradient_scaffold_test.dart lib/screens/auth/login_screen.dart
git commit -m "refactor(auth): one gradient scaffold for the unauthenticated screens

Four copies of two gradient stops, a SafeArea and a translucent back button.
Login adopts it here; the wizard and forgot-password follow."
```

---

### Task 10: StepWizard

The shell both flows become. Built and tested standalone — nothing adopts it until Task 11.

**Files:**
- Create: `lib/screens/auth/registration/step_wizard.dart`
- Test: `test/screens/auth/step_wizard_test.dart`

**Interfaces:**
- Consumes: `AuthGradientScaffold`, `kAuthGradient` from Task 9.
- Produces:
  - `class WizardStep { const WizardStep({required String title, required String subtitle, required Widget Function(BuildContext context, VoidCallback onNext) builder}); }`
  - `class StepWizard extends StatefulWidget` with `const StepWizard({required List<WizardStep> steps, required Future<void> Function() onComplete, VoidCallback? onExit, void Function(int step)? onStepChanged, bool isBusy = false})`
  - `class StepWizardState` — public, not private, so Task 11's draft-resume can reach `void jumpToStep(int index)` and `int get currentStep` through a `GlobalKey<StepWizardState>`. There is no separate controller class; the state is the controller.

- [ ] **Step 1: Write the failing test**

Create `test/screens/auth/step_wizard_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/screens/auth/registration/step_wizard.dart';

/// Two trivial steps: each renders its name and a button that advances.
List<WizardStep> _steps({VoidCallback? onLastNext}) => [
      WizardStep(
        title: 'First',
        subtitle: 'the first one',
        builder: (context, onNext) => Column(
          children: [
            const Text('step-one-body'),
            ElevatedButton(onPressed: onNext, child: const Text('next-1')),
          ],
        ),
      ),
      WizardStep(
        title: 'Second',
        subtitle: 'the second one',
        builder: (context, onNext) => Column(
          children: [
            const Text('step-two-body'),
            ElevatedButton(onPressed: onNext, child: const Text('next-2')),
          ],
        ),
      ),
    ];

Widget _host({
  required List<WizardStep> steps,
  Future<void> Function()? onComplete,
  VoidCallback? onExit,
  void Function(int)? onStepChanged,
  GlobalKey<StepWizardState>? wizardKey,
}) {
  return MaterialApp(
    home: StepWizard(
      key: wizardKey,
      steps: steps,
      onComplete: onComplete ?? () async {},
      onExit: onExit,
      onStepChanged: onStepChanged,
    ),
  );
}

void main() {
  testWidgets('opens on the first step and shows its title and subtitle',
      (tester) async {
    await tester.pumpWidget(_host(steps: _steps()));

    expect(find.text('First'), findsOneWidget);
    expect(find.text('the first one'), findsOneWidget);
    expect(find.text('step-one-body'), findsOneWidget);
    expect(find.text('Step 1 of 2'), findsOneWidget);
  });

  testWidgets('onNext advances and updates the header', (tester) async {
    await tester.pumpWidget(_host(steps: _steps()));

    await tester.tap(find.text('next-1'));
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Step 2 of 2'), findsOneWidget);
  });

  testWidgets('back returns to the previous step', (tester) async {
    await tester.pumpWidget(_host(steps: _steps()));

    await tester.tap(find.text('next-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('back on the first step calls onExit instead', (tester) async {
    var exited = false;
    await tester.pumpWidget(
      _host(steps: _steps(), onExit: () => exited = true),
    );

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(exited, isTrue);
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('onNext on the LAST step calls onComplete, not a page turn',
      (tester) async {
    var completed = 0;
    await tester.pumpWidget(
      _host(steps: _steps(), onComplete: () async => completed++),
    );

    await tester.tap(find.text('next-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('next-2'));
    await tester.pumpAndSettle();

    expect(completed, 1);
  });

  testWidgets('onComplete cannot be entered twice concurrently',
      (tester) async {
    var completed = 0;
    final gate = Completer<void>();
    await tester.pumpWidget(
      _host(
        steps: _steps(),
        onComplete: () async {
          completed++;
          await gate.future;
        },
      ),
    );

    await tester.tap(find.text('next-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('next-2'));
    await tester.pump();
    await tester.tap(find.text('next-2'));
    await tester.pump();

    expect(completed, 1);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('onStepChanged fires with each new index', (tester) async {
    final seen = <int>[];
    await tester.pumpWidget(
      _host(steps: _steps(), onStepChanged: seen.add),
    );

    await tester.tap(find.text('next-1'));
    await tester.pumpAndSettle();

    expect(seen, [1]);
  });

  testWidgets('jumpToStep moves without animating through the middle',
      (tester) async {
    final key = GlobalKey<StepWizardState>();
    await tester.pumpWidget(_host(steps: _steps(), wizardKey: key));

    key.currentState!.jumpToStep(1);
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
  });
}
```

Add `import 'dart:async';` at the top of the test file for `Completer`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/screens/auth/step_wizard_test.dart`
Expected: FAIL — `Target of URI doesn't exist`.

- [ ] **Step 3: Write the implementation**

Create `lib/screens/auth/registration/step_wizard.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:flame/screens/auth/widgets/auth_gradient_scaffold.dart';

/// One page of a [StepWizard].
///
/// [builder] receives the callback that advances — the step decides when it is
/// satisfied, the wizard decides where "forward" goes.
class WizardStep {
  const WizardStep({
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final Widget Function(BuildContext context, VoidCallback onNext) builder;
}

/// The shell shared by registration and social profile completion.
///
/// Owns the header, the progress indicator, the step-info block, the
/// PageController and both directions of movement. It knows nothing about auth
/// state, photos, or what completing means — the two flows differ only in their
/// step list and their [onComplete], which is the whole reason they were two
/// near-identical 500-line widgets before.
class StepWizard extends StatefulWidget {
  const StepWizard({
    super.key,
    required this.steps,
    required this.onComplete,
    this.onExit,
    this.onStepChanged,
    this.isBusy = false,
  });

  final List<WizardStep> steps;

  /// Invoked instead of a page turn when the last step advances. Re-entry is
  /// blocked while it is in flight.
  final Future<void> Function() onComplete;

  /// Back from step 0. Null makes step 0 a dead end with no button.
  final VoidCallback? onExit;

  /// Fires with the new index after every move. The draft save hook.
  final void Function(int step)? onStepChanged;

  /// Drives nothing visually here — steps read it themselves — but is accepted
  /// so a busy flow can be described in one place.
  final bool isBusy;

  @override
  StepWizardState createState() => StepWizardState();
}

/// Public so a host can drive [jumpToStep] through a `GlobalKey`. The draft
/// resume prompt needs exactly that and nothing more.
class StepWizardState extends State<StepWizard> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _completing = false;

  int get currentStep => _currentStep;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Moves straight to [index] with no intermediate animation.
  void jumpToStep(int index) {
    final target = index.clamp(0, widget.steps.length - 1);
    setState(() => _currentStep = target);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(target);
    }
  }

  void _handleNext() {
    if (_currentStep < widget.steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _handleComplete();
  }

  Future<void> _handleComplete() async {
    // A double tap on the final button must not register twice.
    if (_completing) return;
    setState(() => _completing = true);
    try {
      await widget.onComplete();
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  void _handleBack() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    widget.onExit?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AuthGradientScaffold(
      scrollable: false,
      child: Column(
        children: [
          _buildHeader().animate().fadeIn(duration: 400.ms),
          const SizedBox(height: 16),
          _buildProgressIndicator()
              .animate()
              .fadeIn(delay: 100.ms, duration: 400.ms),
          const SizedBox(height: 24),
          _buildStepInfo()
              .animate()
              .fadeIn(delay: 200.ms, duration: 400.ms)
              .slideX(begin: -0.1, end: 0, delay: 200.ms, duration: 400.ms),
          const SizedBox(height: 24),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                setState(() => _currentStep = index);
                widget.onStepChanged?.call(index);
              },
              children: [
                for (final step in widget.steps)
                  step.builder(context, _handleNext),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    // The back affordance is absent, not disabled, when there is nowhere to go.
    final canGoBack = _currentStep > 0 || widget.onExit != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (canGoBack)
            IconButton(
              onPressed: _handleBack,
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            )
          else
            const SizedBox(width: 48),
          Text(
            'Step ${_currentStep + 1} of ${widget.steps.length}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 48), // balances the back button
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    final total = widget.steps.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: List.generate(total, (index) {
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: index < total - 1 ? 8 : 0),
              decoration: BoxDecoration(
                color: index <= _currentStep
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepInfo() {
    final step = widget.steps[_currentStep];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.subtitle,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}
```

`AuthGradientScaffold` renders its own back button only when `onBack` is passed; the wizard passes none and draws its own inside the header row, because the header also carries the step counter.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/screens/auth/step_wizard_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/auth/registration/step_wizard.dart test/screens/auth/step_wizard_test.dart
git commit -m "feat(auth): a step wizard shell for both registration flows

Header, progress, step info, PageController and both directions of movement in
one place. Knows nothing about auth, photos, or what completing means. Nothing
adopts it yet."
```

---

### Task 11: RegistrationFlow becomes a StepWizard config

**Files:**
- Modify: `lib/screens/auth/registration/registration_flow.dart` (rewrite the widget body; `RegistrationData` and `resumeStepFor` stay)
- Test: `test/screens/auth/registration_no_verify_step_test.dart`, `registration_consent_test.dart`, `registration_resume_test.dart` (all existing, must keep passing)

**Interfaces:**
- Consumes: `StepWizard`, `WizardStep`, `StepWizardState` (Task 10); `PhotoCompressor` (Task 7); `showAuthSnackBar` (Task 8); `resumeStepFor` (Task 4).
- Produces: `class RegistrationFlow` unchanged in name and constructor, so `welcome_screen.dart:248` is untouched.

- [ ] **Step 1: Rewrite the state class**

Replace everything in `lib/screens/auth/registration/registration_flow.dart` between `class _RegistrationFlowState` and the closing brace before `resumeStepFor`, keeping `RegistrationData` at the top and `resumeStepFor` at the bottom:

```dart
class _RegistrationFlowState extends ConsumerState<RegistrationFlow> {
  final GlobalKey<StepWizardState> _wizardKey = GlobalKey<StepWizardState>();
  final RegistrationData _data = RegistrationData();
  final RegistrationDraft _draft = const RegistrationDraft();
  bool _isUploading = false;
  bool _registrationComplete = false;

  static const int _totalSteps = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferResume());
  }

  Future<void> _maybeOfferResume() async {
    final saved = await _draft.load();
    if (saved == null || !mounted) return;
    if (saved.step <= 0 && saved.data.email.isEmpty) {
      await _draft.clear();
      return;
    }

    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Resume your signup?'),
        content: const Text(
          'We saved your progress. Pick up where you left off, or start over.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Start Over'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resume'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (resume == true) {
      _restoreFrom(saved.data, saved.step);
    } else {
      await _draft.clear();
    }
  }

  void _restoreFrom(RegistrationData data, int step) {
    _data
      ..email = data.email
      ..name = data.name
      ..age = data.age
      ..gender = data.gender
      ..lookingFor = data.lookingFor
      ..bio = data.bio
      ..interests = data.interests
      ..photoFiles = data.photoFiles
      ..latitude = data.latitude
      ..longitude = data.longitude;

    _wizardKey.currentState?.jumpToStep(
      resumeStepFor(
        password: _data.password,
        savedStep: step,
        totalSteps: _totalSteps,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (_registrationComplete &&
          (next.isAuthenticated || next.isProfileIncomplete)) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      if (next.error != null) {
        showAuthSnackBar(
          context,
          message: next.error!,
          type: AuthSnackBarType.error,
        );
        ref.read(authProvider.notifier).clearError();
      }
    });

    final busy = authState.isLoading || _isUploading;

    return StepWizard(
      key: _wizardKey,
      isBusy: busy,
      onStepChanged: (step) => _draft.save(_data, step),
      onExit: () {
        // Explicit back-out to welcome — discard the saved draft.
        _draft.clear();
        Navigator.of(context).pop();
      },
      onComplete: _registerNewAccount,
      steps: [
        WizardStep(
          title: 'Create Account',
          subtitle: 'Enter your email and create a password',
          builder: (context, onNext) =>
              StepEmailPassword(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: 'About You',
          subtitle: 'Tell us a bit about yourself',
          builder: (context, onNext) =>
              StepProfileInfo(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: 'Looking For',
          subtitle: 'Who would you like to meet?',
          builder: (context, onNext) =>
              StepLookingFor(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: 'Your Interests',
          subtitle: 'What makes you, you?',
          builder: (context, onNext) =>
              StepBioInterests(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: 'Add Photos',
          subtitle: 'Show off your best self',
          builder: (context, onNext) => StepPhotos(
            data: _data,
            isLoading: busy,
            onComplete: onNext,
          ),
        ),
      ],
    );
  }

  Future<void> _registerNewAccount() async {
    setState(() => _isUploading = true);

    try {
      final locationResult = await LocationService().getCurrentPosition();
      if (!mounted) return;

      if (!locationResult.success) {
        setState(() => _isUploading = false);
        _showLocationError(locationResult.error ?? 'Failed to get location');
        return;
      }

      _data.latitude = locationResult.latitude;
      _data.longitude = locationResult.longitude;

      final photoUrls = await _uploadPhotosForRegistration();
      if (!mounted) return;

      if (photoUrls.isEmpty) {
        setState(() => _isUploading = false);
        showAuthSnackBar(
          context,
          message: 'Failed to upload photos. Please try again.',
          type: AuthSnackBarType.error,
        );
        return;
      }

      final success = await ref.read(authProvider.notifier).register(
            email: _data.email,
            password: _data.password,
            name: _data.name,
            age: _data.age,
            gender: _data.gender,
            lookingFor: _data.lookingFor,
            bio: _data.bio,
            interests: _data.interests,
            photos: photoUrls,
            latitude: _data.latitude!,
            longitude: _data.longitude!,
          );
      if (!mounted) return;
      setState(() => _isUploading = false);

      if (success) {
        await _draft.clear();
        if (!mounted) return;
        setState(() => _registrationComplete = true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      showAuthSnackBar(
        context,
        message: 'Error: ${e.toString()}',
        type: AuthSnackBarType.error,
      );
    }
  }

  Future<List<String>> _uploadPhotosForRegistration() async {
    if (_data.photoFiles.isEmpty) return [];

    final userService = UserService();

    String tempPath;
    try {
      tempPath = (await getTemporaryDirectory()).path;
    } catch (_) {
      // path_provider is unavailable on some simulators.
      tempPath = Directory.systemTemp.path;
    }

    // Index each file so compression paths stay stable and collision-free
    // even though the uploads run concurrently.
    final indexOf = <File, int>{};
    for (var i = 0; i < _data.photoFiles.length; i++) {
      indexOf[_data.photoFiles[i]] = i;
    }

    return const PhotoUploader().upload(
      _data.photoFiles,
      uploadOne: (file, {required bool isPrimary}) async {
        final i = indexOf[file] ?? 0;
        try {
          final compressed = await const PhotoCompressor()
              .compress(file, tempDir: tempPath, index: i);

          final result = await userService.uploadPhotoForRegistration(
            compressed,
            isPrimary: isPrimary,
          );

          if (result.success && result.data != null) {
            return UploadOutcome(success: true, url: result.data!.url);
          }
          debugPrint('Failed to upload photo ${i + 1}: ${result.error}');
          return const UploadOutcome(success: false);
        } catch (e) {
          debugPrint('Error uploading photo ${i + 1}: $e');
          return const UploadOutcome(success: false);
        }
      },
    );
  }

  void _showLocationError(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Required'),
        content: Text(
          '$error\n\nFlame needs your location to find matches near you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await LocationService().openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
```

Update the imports: add `step_wizard.dart`, `package:flame/core/image/photo_compressor.dart`, `package:flame/screens/auth/widgets/auth_snackbar.dart`; drop `package:flutter_animate/flutter_animate.dart`, `package:image/image.dart`, and `package:flame/theme/app_theme.dart` if nothing else in the file uses them.

- [ ] **Step 2: Run the existing registration tests**

Run: `flutter test test/screens/auth/`
Expected: PASS. `registration_no_verify_step_test.dart` asserts the flow has five steps and no verification step; `registration_consent_test.dart` asserts the terms checkbox gates Continue. Both must still pass unmodified — if either fails, the rewrite changed behaviour it should not have.

- [ ] **Step 3: Run the full suite and the analyzer**

Run: `flutter test && flutter analyze lib/`
Expected: PASS, clean.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/auth/registration/registration_flow.dart
git commit -m "refactor(auth): registration becomes a step list and a callback

The chrome, the PageController and both directions of movement now live in
StepWizard. RegistrationFlow keeps its name and constructor, so welcome_screen
is untouched."
```

---

### Task 12: SocialProfileCompletionFlow becomes a StepWizard config

Also brings its photo upload onto `PhotoUploader`, which is what stopped the two paths agreeing in the first place.

**Files:**
- Modify: `lib/screens/auth/registration/social_profile_completion_flow.dart` (full rewrite)
- Test: `test/screens/auth/social_completion_test.dart` (create)

**Interfaces:**
- Consumes: `StepWizard`, `WizardStep` (Task 10); `PhotoUploader`, `UploadOutcome` (existing, `photo_uploader.dart`); `PhotoCompressor` (Task 7); `updateProfile(gender:)` (Task 3).
- Produces: `class SocialProfileCompletionFlow` unchanged in name and constructor, so `main.dart:92` is untouched.

- [ ] **Step 1: Write the failing test**

Create `test/screens/auth/social_completion_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/screens/auth/registration/social_profile_completion_flow.dart';
import 'package:flame/screens/auth/registration/step_wizard.dart';

void main() {
  testWidgets('opens on a four-step wizard, with no email/password step',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          supportedLocales: kSupportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: SocialProfileCompletionFlow(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(StepWizard), findsOneWidget);
    // A social user already has credentials — asking for a password again
    // would be nonsense, so the flow starts at profile info.
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.text('About You'), findsOneWidget);
  });

  testWidgets('step 1 offers no back affordance — there is nowhere to go',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          locale: Locale('en'),
          supportedLocales: kSupportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: SocialProfileCompletionFlow(),
        ),
      ),
    );
    await tester.pump();

    // The user is already authenticated; backing out would strand them
    // between signed-in and unusable.
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsNothing);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/screens/auth/social_completion_test.dart`
Expected: FAIL — `StepWizard` not found; the flow still builds its own scaffold.

- [ ] **Step 3: Rewrite the file**

Replace `lib/screens/auth/registration/social_profile_completion_flow.dart` in full:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/image/photo_compressor.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/screens/auth/widgets/auth_snackbar.dart';
import 'package:flame/services/user_service.dart';
import 'photo_uploader.dart';
import 'registration_flow.dart';
import 'step_wizard.dart';
import 'steps/step_bio_interests.dart';
import 'steps/step_looking_for.dart';
import 'steps/step_photos.dart';
import 'steps/step_profile_info.dart';

/// Profile completion for a user who signed in with Google, Apple or Facebook.
///
/// The same wizard registration uses, minus the email/password step — a social
/// user already has credentials. No exit: they are authenticated but their
/// profile is unusable, so backing out would strand them between the two.
class SocialProfileCompletionFlow extends ConsumerStatefulWidget {
  const SocialProfileCompletionFlow({super.key});

  @override
  ConsumerState<SocialProfileCompletionFlow> createState() =>
      _SocialProfileCompletionFlowState();
}

class _SocialProfileCompletionFlowState
    extends ConsumerState<SocialProfileCompletionFlow> {
  final RegistrationData _data = RegistrationData();
  bool _isUploading = false;
  bool _prefilled = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Pre-fill the name the provider gave us — once. Doing this unconditionally
    // in build() meant every rebuild fought whatever the user had typed.
    if (!_prefilled && authState.user != null) {
      _data.name = authState.user!.name;
      _prefilled = true;
    }

    return StepWizard(
      isBusy: _isUploading,
      onComplete: _completeSocialProfile,
      steps: [
        WizardStep(
          title: 'About You',
          subtitle: 'Tell us a bit about yourself',
          builder: (context, onNext) =>
              StepProfileInfo(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: 'Looking For',
          subtitle: 'Who would you like to meet?',
          builder: (context, onNext) =>
              StepLookingFor(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: 'Your Interests',
          subtitle: 'What makes you, you?',
          builder: (context, onNext) =>
              StepBioInterests(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: 'Add Photos',
          subtitle: 'Show off your best self',
          builder: (context, onNext) => StepPhotos(
            data: _data,
            isLoading: _isUploading,
            onComplete: onNext,
          ),
        ),
      ],
    );
  }

  Future<void> _completeSocialProfile() async {
    setState(() => _isUploading = true);
    final userService = UserService();

    try {
      final profileResult = await userService.updateProfile(
        name: _data.name,
        bio: _data.bio,
        interests: _data.interests,
        lookingFor: _data.lookingFor,
        gender: _data.gender,
        age: _data.age,
      );
      if (!mounted) return;

      if (!profileResult.success) {
        setState(() => _isUploading = false);
        showAuthSnackBar(
          context,
          message: profileResult.error ?? 'Failed to update profile',
          type: AuthSnackBarType.error,
        );
        return;
      }

      await _uploadPhotos(userService);
      if (!mounted) return;

      final userResult = await userService.getCurrentUser();
      if (!mounted) return;
      if (userResult.success && userResult.data != null) {
        ref.read(authProvider.notifier).updateUser(userResult.data!);
      }

      setState(() => _isUploading = false);
      ref.read(authProvider.notifier).markAuthenticated();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      showAuthSnackBar(
        context,
        message: 'Error: ${e.toString()}',
        type: AuthSnackBarType.error,
      );
    }
  }

  /// The same uploader registration uses — parallel, with one retry per photo.
  /// This path was a sequential `for` loop that swallowed every error, which is
  /// exactly the drift a shared wizard is meant to stop.
  Future<void> _uploadPhotos(UserService userService) async {
    if (_data.photoFiles.isEmpty) return;

    String tempPath;
    try {
      final dir = await Directory.systemTemp.createTemp('flame_photos');
      tempPath = dir.path;
    } catch (_) {
      tempPath = Directory.systemTemp.path;
    }

    final indexOf = <File, int>{};
    for (var i = 0; i < _data.photoFiles.length; i++) {
      indexOf[_data.photoFiles[i]] = i;
    }

    await const PhotoUploader().upload(
      _data.photoFiles,
      uploadOne: (file, {required bool isPrimary}) async {
        final i = indexOf[file] ?? 0;
        try {
          final compressed = await const PhotoCompressor()
              .compress(file, tempDir: tempPath, index: i);
          final result =
              await userService.uploadPhoto(compressed, isPrimary: isPrimary);
          if (result.success) {
            return UploadOutcome(success: true, url: result.data?.url);
          }
          debugPrint('Failed to upload photo ${i + 1}: ${result.error}');
          return const UploadOutcome(success: false);
        } catch (e) {
          debugPrint('Error uploading photo ${i + 1}: $e');
          return const UploadOutcome(success: false);
        }
      },
    );
  }
}
```

`UserService.uploadPhoto` returns `ServiceResult<Photo>` (`user_service.dart:123`), the same shape `uploadPhotoForRegistration` returns, so `result.data?.url` is correct as written. The two differ only in endpoint — `/users/me/photos` versus `/auth/upload-photo` — which is why the social flow cannot simply call the registration one.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/screens/auth/social_completion_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 5: Run the full suite and the analyzer**

Run: `flutter test && flutter analyze lib/`
Expected: PASS, clean. The file should be roughly 170 lines, down from 290.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/auth/registration/social_profile_completion_flow.dart test/screens/auth/social_completion_test.dart
git commit -m "refactor(auth): social completion becomes a step list too

Both flows are now configs of one wizard, and both upload photos through the
same PhotoUploader. The social path was a sequential loop that swallowed every
error — the same drift that lost gender."
```

---

### Task 13: Delete the dead surface

**Files:**
- Delete: `lib/screens/auth/registration/steps/step_verify_email.dart`
- Modify: `lib/services/auth_service.dart:113-141`, `:196-216`
- Modify: `lib/providers/auth_provider.dart:8-14`, `:270-278`
- Modify: `test/providers/realtime_lifecycle_test.dart:41-46`

**Interfaces:**
- Removes: `AuthService.verifyEmail`, `AuthService.resendVerificationCode`, `AuthService.resetPassword`, `AuthStatus.registering`, `AuthNotifier.startRegistration`, `AuthNotifier.cancelRegistration`, `StepVerifyEmail`.

- [ ] **Step 1: Confirm nothing references them**

Run:
```bash
grep -rn "StepVerifyEmail\|step_verify_email" lib/ test/
grep -rn "verifyEmail\|resendVerificationCode\|resetPassword" lib/ test/
grep -rn "AuthStatus.registering\|startRegistration\|cancelRegistration" lib/ test/
```
Expected: the first two produce output only from the files being deleted or edited in this task. The third produces `auth_provider.dart` and `test/providers/realtime_lifecycle_test.dart:44` only. If anything else appears, stop — the reference is real and this task's premise is wrong.

- [ ] **Step 2: Delete the file**

```bash
git rm lib/screens/auth/registration/steps/step_verify_email.dart
```

- [ ] **Step 3: Remove the three AuthService methods**

Delete `verifyEmail`, `resendVerificationCode` and `resetPassword` from `lib/services/auth_service.dart`. Keep `forgotPassword` and `changePassword`: `forgot_password_screen.dart` calls one and `settings_screen.dart:537` the other, both behind `forgotPasswordEnabled`.

- [ ] **Step 4: Remove the unused auth status**

In `lib/providers/auth_provider.dart`, delete `registering,` from the `AuthStatus` enum and delete both `startRegistration()` and `cancelRegistration()` with their comments. Registration is a pushed route, not an auth status — that is why nothing ever called them.

- [ ] **Step 5: Update the enumerating test**

In `test/providers/realtime_lifecycle_test.dart`, remove `AuthStatus.registering,` from the list in the 'every non-authenticated status stops it' test. The remaining three still prove the rule.

This is the one sanctioned edit to a pre-existing test in this plan — it enumerates an enum member that no longer exists, so leaving it would not compile.

- [ ] **Step 6: Run the suite and the analyzer**

Run: `flutter test && flutter analyze lib/`
Expected: PASS, clean.

- [ ] **Step 7: Commit**

```bash
git add -A lib/ test/
git commit -m "chore(auth): delete the unreachable surface

step_verify_email.dart had zero references in lib/ or test/, and was the only
caller of AuthService.verifyEmail and resendVerificationCode. resetPassword had
no caller at all. AuthStatus.registering and its two transitions were never
invoked — registration is a pushed route, not an auth status, which is why."
```

---

### Task 14: Rebuild forgot_password_screen on the kit

Unreachable behind `forgotPasswordEnabled`, but it is the one auth file matching nothing else in the codebase. Rebuilt now so it is ready when the endpoints land.

**Files:**
- Modify: `lib/screens/auth/forgot_password_screen.dart` (full rewrite)
- Modify: `lib/l10n/app_en.arb`
- Test: `test/screens/auth/forgot_password_test.dart` (create)

**Interfaces:**
- Consumes: `AuthGradientScaffold` (Task 9), `showAuthSnackBar` (Task 8), `AuthValidators` (Task 1), `translateApiError` (existing).

- [ ] **Step 1: Add the ARB keys**

```json
  "forgotPasswordTitle": "Forgot\nPassword?",
  "@forgotPasswordTitle": {
    "description": "Heading on the forgot-password screen before a reset email is sent"
  },
  "forgotPasswordSubtitle": "No worries, we'll send you reset instructions",
  "@forgotPasswordSubtitle": {
    "description": "Subheading on the forgot-password screen before sending"
  },
  "forgotPasswordSubmit": "Send reset link",
  "@forgotPasswordSubmit": {
    "description": "Button that requests a password reset email"
  },
  "forgotPasswordSentTitle": "Check Your\nEmail",
  "@forgotPasswordSentTitle": {
    "description": "Heading after a reset email has been sent"
  },
  "forgotPasswordSentSubtitle": "We've sent a reset link to your email",
  "@forgotPasswordSentSubtitle": {
    "description": "Subheading after a reset email has been sent"
  },
  "forgotPasswordSentHeading": "Email sent",
  "@forgotPasswordSentHeading": {
    "description": "Heading inside the confirmation card"
  },
  "forgotPasswordSentBody": "Please check your inbox and follow the instructions to reset your password.",
  "@forgotPasswordSentBody": {
    "description": "Body text inside the confirmation card"
  },
  "forgotPasswordBackToLogin": "Back to login",
  "@forgotPasswordBackToLogin": {
    "description": "Button returning to the login screen from the confirmation card"
  },
  "forgotPasswordRetry": "Didn't receive the email? Try again",
  "@forgotPasswordRetry": {
    "description": "Link that returns to the email form to re-request a reset"
  }
```

Run `flutter gen-l10n`.

- [ ] **Step 2: Write the failing test**

Create `test/screens/auth/forgot_password_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/screens/auth/forgot_password_screen.dart';
import 'package:flame/widgets/kit/kit.dart';

Widget _host() => const ProviderScope(
      child: MaterialApp(
        locale: Locale('en'),
        supportedLocales: kSupportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ForgotPasswordScreen(),
      ),
    );

void main() {
  testWidgets('uses the design-system input and button, not raw Material',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.byType(AppInput), findsOneWidget);
    expect(find.byType(AppButton), findsOneWidget);
  });

  testWidgets('an invalid address is rejected without a request',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'not-an-email');
    await tester.tap(find.byType(AppButton));
    await tester.pump();

    expect(find.text('Please enter a valid email'), findsOneWidget);
  });

  testWidgets('plus addressing is accepted — the old regex rejected it',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump();

    await tester.enterText(find.byType(TextFormField), 'ada+reset@gmail.com');
    await tester.tap(find.byType(AppButton));
    await tester.pump();

    expect(find.text('Please enter a valid email'), findsNothing);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `flutter test test/screens/auth/forgot_password_test.dart`
Expected: FAIL — the screen builds a raw `TextFormField` and `ElevatedButton`, so `AppInput`/`AppButton` are not found.

- [ ] **Step 4: Rewrite the screen**

Replace `lib/screens/auth/forgot_password_screen.dart` in full:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/validation/auth_validators.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/screens/auth/widgets/auth_gradient_scaffold.dart';
import 'package:flame/screens/auth/widgets/auth_snackbar.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/kit/kit.dart';

/// Requests a password-reset email.
///
/// Gated off — `EnvConfig.current.forgotPasswordEnabled` is false in both
/// presets and `/auth/forgot-password` does not exist server-side yet. Kept in
/// the codebase, and in the codebase's shape, so it is ready the day it does.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.error == null) return;
      showAuthSnackBar(
        context,
        message: next.error!,
        type: AuthSnackBarType.error,
      );
      ref.read(authProvider.notifier).clearError();
    });

    return AuthGradientScaffold(
      onBack: () => Navigator.of(context).pop(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            _buildHeader()
                .animate()
                .fadeIn(delay: 100.ms, duration: 500.ms)
                .slideX(begin: -0.1, end: 0, delay: 100.ms, duration: 500.ms),
            const SizedBox(height: 48),
            if (_emailSent)
              _buildSuccessCard()
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .scale(
                    begin: const Offset(0.95, 0.95),
                    end: const Offset(1, 1),
                  )
            else
              _buildFormCard(authState)
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 600.ms)
                  .slideY(begin: 0.1, end: 0, delay: 200.ms, duration: 600.ms),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _emailSent
              ? context.l10n.forgotPasswordSentTitle
              : context.l10n.forgotPasswordTitle,
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _emailSent
              ? context.l10n.forgotPasswordSentSubtitle
              : context.l10n.forgotPasswordSubtitle,
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard(AuthState authState) {
    return AppCard(
      padding: const EdgeInsets.all(24),
      borderRadius: AppRadius.borderXXL,
      boxShadow: AppShadows.lg,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppInput(
              controller: _emailController,
              label: context.l10n.loginEmailLabel,
              hint: context.l10n.loginEmailHint,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              prefixIcon: Icons.email_outlined,
              validator: AuthValidators(context.l10n).email,
              onSubmitted: (_) => _handleSubmit(),
            ),
            const SizedBox(height: 32),
            AppButton(
              text: context.l10n.forgotPasswordSubmit,
              size: AppButtonSize.large,
              isFullWidth: true,
              isLoading: authState.isLoading,
              onPressed: _handleSubmit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    return AppCard(
      padding: const EdgeInsets.all(24),
      borderRadius: AppRadius.borderXXL,
      boxShadow: AppShadows.lg,
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              size: 40,
              color: AppTheme.successColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.l10n.forgotPasswordSentHeading,
            style: AppTypography.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.forgotPasswordSentBody,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.gray600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            text: context.l10n.forgotPasswordBackToLogin,
            size: AppButtonSize.large,
            isFullWidth: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 8),
          AppButton(
            text: context.l10n.forgotPasswordRetry,
            variant: AppButtonVariant.ghost,
            isFullWidth: true,
            onPressed: () => setState(() => _emailSent = false),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref
        .read(authProvider.notifier)
        .forgotPassword(_emailController.text.trim());
    if (!mounted) return;

    if (success) setState(() => _emailSent = true);
  }
}
```

`AppTypography.headlineSmall` is defined at `app_theme.dart:257` — use it as written, do not add a style.

The `translateApiError` requirement is satisfied through `AuthState.error`, which is already populated from `AuthResult.error`; when Task 15's follow-up work threads `errorCode` through the provider this screen gains proper translation for free. Until then it shows the backend's message, which is what login does too.

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/screens/auth/forgot_password_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 6: Verify the deprecation is gone**

Run: `grep -rn "withOpacity" lib/screens/auth/`
Expected: no output.

- [ ] **Step 7: Run the suite and the analyzer**

Run: `flutter test && flutter analyze lib/`
Expected: PASS, clean.

- [ ] **Step 8: Commit**

```bash
git add lib/screens/auth/forgot_password_screen.dart test/screens/auth/forgot_password_test.dart lib/l10n/
git commit -m "refactor(auth): forgot-password joins the rest of the codebase

Deprecated withOpacity, raw TextFormField and ElevatedButton where the kit
exists, twelve hardcoded strings, and its own copy of the email regex. Still
gated off — the endpoint still does not exist — but no longer the one file
matching nothing else."
```

---

### Task 15: Localise the registration flow

Roughly 100 hardcoded English strings across the flow and its steps.

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/screens/auth/registration/registration_flow.dart`, `social_profile_completion_flow.dart`, `steps/step_profile_info.dart`, `steps/step_looking_for.dart`, `steps/step_bio_interests.dart`, `steps/step_photos.dart`, `steps/step_email_password.dart`
- Test: `test/l10n/registration_localised_test.dart` (create)

**Interfaces:**
- Consumes: `context.l10n` from `lib/core/i18n/build_context_ext.dart`.

- [ ] **Step 1: Write the failing test**

Create `test/l10n/registration_localised_test.dart`. This is a source-level guard rather than a widget test — it is what stops the next hardcoded string landing.

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Files whose user-facing copy must come from the ARBs.
const _guarded = [
  'lib/screens/auth/registration/registration_flow.dart',
  'lib/screens/auth/registration/social_profile_completion_flow.dart',
  'lib/screens/auth/registration/step_wizard.dart',
  'lib/screens/auth/registration/steps/step_email_password.dart',
  'lib/screens/auth/registration/steps/step_profile_info.dart',
  'lib/screens/auth/registration/steps/step_looking_for.dart',
  'lib/screens/auth/registration/steps/step_bio_interests.dart',
  'lib/screens/auth/registration/steps/step_photos.dart',
];

/// A quoted sentence: starts with a capital, contains a space, three or more
/// characters. Deliberately crude — it catches copy, not identifiers.
final _sentence = RegExp(r"""['"][A-Z][a-z]+ [^'"]{3,}['"]""");

/// Lines that are allowed to carry an English sentence: debug output, comments,
/// asset paths, and API string constants.
bool _exempt(String line) {
  final t = line.trimLeft();
  return t.startsWith('//') ||
      t.startsWith('///') ||
      t.startsWith('*') ||
      t.contains('debugPrint') ||
      t.contains('assets/');
}

void main() {
  for (final path in _guarded) {
    test('$path has no hardcoded user-facing copy', () {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is missing');

      final offenders = <String>[];
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_exempt(lines[i])) continue;
        if (_sentence.hasMatch(lines[i])) {
          offenders.add('  ${i + 1}: ${lines[i].trim()}');
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Move these into lib/l10n/app_en.arb and read them through '
            'context.l10n:\n${offenders.join('\n')}',
      );
    });
  }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/l10n/registration_localised_test.dart`
Expected: FAIL, with a list of every hardcoded string per file. That list is the work order for the next step.

- [ ] **Step 3: Add the ARB keys**

For every string the test named, add a key to `lib/l10n/app_en.arb` with an `@key` description. Use the `register*` prefix for registration-only copy and `wizard*` for the shell. The step titles and subtitles from Tasks 11 and 12 are included — they moved into `WizardStep` literals and are still English in source.

Keys needed, at minimum (add any the test names that are missing here):

```json
  "wizardStepCounter": "Step {current} of {total}",
  "@wizardStepCounter": {
    "description": "Progress label above a registration wizard's step",
    "placeholders": {
      "current": { "type": "int" },
      "total": { "type": "int" }
    }
  },
  "registerStepAccountTitle": "Create Account",
  "@registerStepAccountTitle": { "description": "Title of the email/password step" },
  "registerStepAccountSubtitle": "Enter your email and create a password",
  "@registerStepAccountSubtitle": { "description": "Subtitle of the email/password step" },
  "registerStepAboutTitle": "About You",
  "@registerStepAboutTitle": { "description": "Title of the name/age/gender step" },
  "registerStepAboutSubtitle": "Tell us a bit about yourself",
  "@registerStepAboutSubtitle": { "description": "Subtitle of the name/age/gender step" },
  "registerStepLookingForTitle": "Looking For",
  "@registerStepLookingForTitle": { "description": "Title of the gender-preference step" },
  "registerStepLookingForSubtitle": "Who would you like to meet?",
  "@registerStepLookingForSubtitle": { "description": "Subtitle of the gender-preference step" },
  "registerStepInterestsTitle": "Your Interests",
  "@registerStepInterestsTitle": { "description": "Title of the bio/interests step" },
  "registerStepInterestsSubtitle": "What makes you, you?",
  "@registerStepInterestsSubtitle": { "description": "Subtitle of the bio/interests step" },
  "registerStepPhotosTitle": "Add Photos",
  "@registerStepPhotosTitle": { "description": "Title of the photos step" },
  "registerStepPhotosSubtitle": "Show off your best self",
  "@registerStepPhotosSubtitle": { "description": "Subtitle of the photos step" },
  "registerResumeTitle": "Resume your signup?",
  "@registerResumeTitle": { "description": "Dialog title offering to restore a saved registration draft" },
  "registerResumeBody": "We saved your progress. Pick up where you left off, or start over.",
  "@registerResumeBody": { "description": "Dialog body offering to restore a saved draft" },
  "registerResumeStartOver": "Start over",
  "@registerResumeStartOver": { "description": "Discards the saved draft" },
  "registerResumeContinue": "Resume",
  "@registerResumeContinue": { "description": "Restores the saved draft" },
  "registerContinue": "Continue",
  "@registerContinue": { "description": "Advances to the next registration step" },
  "registerLocationRequiredTitle": "Location required",
  "@registerLocationRequiredTitle": { "description": "Dialog title when location permission is missing at signup" },
  "registerLocationRequiredBody": "Flame needs your location to find matches near you.",
  "@registerLocationRequiredBody": { "description": "Explains why location is needed, shown under the platform error" },
  "registerOpenSettings": "Open settings",
  "@registerOpenSettings": { "description": "Opens the OS app-settings page" },
  "registerCancel": "Cancel",
  "@registerCancel": { "description": "Dismisses a registration dialog" },
  "registerPhotoUploadFailed": "Failed to upload photos. Please try again.",
  "@registerPhotoUploadFailed": { "description": "Shown when every photo upload failed" },
  "registerProfileUpdateFailed": "Failed to update profile",
  "@registerProfileUpdateFailed": { "description": "Shown when the profile PATCH failed during social completion" },
  "registerGenderRequired": "Please select your gender",
  "@registerGenderRequired": { "description": "Shown when the gender chips are untouched" },
  "registerLookingForRequired": "Please select who you'd like to see",
  "@registerLookingForRequired": { "description": "Shown when no gender preference is chosen" },
  "registerInterestsMax": "Maximum 5 interests allowed",
  "@registerInterestsMax": { "description": "Shown when a sixth interest is tapped" },
  "registerInterestsMin": "Pick at least one interest",
  "@registerInterestsMin": { "description": "Shown when advancing with no interests selected" }
```

Run `flutter gen-l10n`.

- [ ] **Step 4: Replace the strings**

Work file by file down the test's output. Two shapes to watch:

`WizardStep` literals in both flows read from `context` — the builder already has one, and the flow's `build` does too:
```dart
        WizardStep(
          title: context.l10n.registerStepAccountTitle,
          subtitle: context.l10n.registerStepAccountSubtitle,
          builder: (context, onNext) =>
              StepEmailPassword(data: _data, onNext: onNext),
        ),
```

The wizard's step counter takes placeholders:
```dart
          Text(
            context.l10n.wizardStepCounter(_currentStep + 1, widget.steps.length),
```

Add `import 'package:flame/core/i18n/build_context_ext.dart';` to any file that does not have it — including `step_wizard.dart`.

- [ ] **Step 5: Run the guard test to verify it passes**

Run: `flutter test test/l10n/registration_localised_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 6: Run the suite and the analyzer**

Run: `flutter test && flutter analyze lib/`
Expected: PASS, clean. Widget tests that find text by an English string still pass — the `en` locale renders identical copy.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/auth/ lib/l10n/ test/l10n/
git commit -m "i18n(auth): registration reads from the ARBs

Roughly 100 hardcoded strings, in a flow whose login and welcome screens were
already fully localised. English only — the other eleven locales are ~214 keys
behind and fall back, so translation stays a content task.

The guard test is the point: it fails on the next hardcoded sentence rather
than waiting for someone to notice."
```

---

### Task 16: Full verification

**Files:** none modified unless a check fails.

- [ ] **Step 1: Full test suite**

Run: `flutter test`
Expected: PASS. The count should exceed the 624 that passed before this plan started — record the new number.

- [ ] **Step 2: Analyzer, whole project**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Confirm every bug from the spec is closed**

```bash
# no regex copies
grep -rn 'w-..]+@' lib/
# no inline auth snackbars
grep -rn "showSnackBar" lib/screens/auth/ lib/widgets/auth/ | grep -v auth_snackbar.dart
# no deprecated opacity in auth
grep -rn "withOpacity" lib/screens/auth/
# the dead surface is gone
grep -rn "StepVerifyEmail\|AuthStatus.registering\|resendVerificationCode" lib/ test/
# gender is sent
grep -n "gender: _data.gender" lib/screens/auth/registration/social_profile_completion_flow.dart
```
Expected: the first four produce no output; the last produces one line.

- [ ] **Step 4: Confirm the two flows actually shrank**

Run: `wc -l lib/screens/auth/registration/registration_flow.dart lib/screens/auth/registration/social_profile_completion_flow.dart lib/screens/auth/registration/step_wizard.dart`
Expected: the two flows total well under their original 842 lines; the wizard is the new shared cost, not an addition on top.

- [ ] **Step 5: Build the app**

Run: `flutter build apk --debug`
Expected: succeeds. A release build is blocked on the keystore (`docs/RELEASE-CHECKLIST.md` item 1) and is not this plan's business.

- [ ] **Step 6: Commit anything outstanding**

```bash
git status
```
Expected: clean. If not, the previous tasks left something uncommitted — commit it with a message naming what it belongs to.

---

## Device check (not a code task)

`docs/RELEASE-CHECKLIST.md` records that nothing has been looked at on a device. This plan rewrites the first screens every user sees, which makes that gap worse, not better. Before merging, run `flutter run --dart-define=APP_ENV=local` on a cabled phone and walk:

- Welcome → Sign in → back, and Welcome → Create account → back.
- Registration all five steps, then background the app mid-flow, relaunch, and take the Resume offer — confirm it lands on step 1 asking for a password again.
- A wrong password on login, to see the snackbar.
- Registration step 1 with an address that already exists, to see the inline error and that "Log in instead" reaches login rather than welcome.
- Dark mode on every one of the above.
