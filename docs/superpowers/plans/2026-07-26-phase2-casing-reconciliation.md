# Phase 2 — Casing Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Flutter app read and write user data correctly against a backend that emits **camelCase** on `/auth/*` and `/users/*` while emitting **snake_case** on `/discover` and other newer endpoints — all parsed by the same `User.fromJson`.

**Architecture:** Keep the existing snake_case keys as the primary read (needed for `/discover`) and add a camelCase fallback for every mismatched field, mirroring the pattern already used for tokens (`tokens['accessToken'] ?? tokens['access_token']`, `auth_service.dart:39`). Extract the `PATCH /users/me` request body into a pure, testable helper that emits camelCase (what the backend reads) so profile edits actually persist.

**Tech Stack:** Flutter, Dart, `flutter_test`. No new dependencies.

## Global Constraints

- API base (prod): `https://api.banatalk.com/flamebackend/v1`. Never use `api.flame.banatalk.com`.
- Response envelope: `{ "success": true, "data": ... }`.
- `User.fromJson` is shared by BOTH camelCase endpoints (`/users/me`, `/auth/*`) and snake_case endpoints (`/discover`) — every field fix MUST accept **both** casings, snake_case first.
- Do not change `User`'s field names, constructor, `copyWith`, or `toJson` key set beyond what a task explicitly specifies.
- Match existing code idiom: inline `a ?? b` fallbacks, not a new abstraction layer.

**Empirically verified (2026-07-26, live prod `GET /users/me` for demo@flame.app):**
- Top-level camelCase keys: `lookingFor` (`"male"`), `isOnline`, `isVerified`, `lastActive`, `createdAt`.
- `preferences` camelCase: `minAge`, `maxAge`, `maxDistance`, `showDistance`, `showOnlineStatus`.
- Tokens camelCase: `accessToken`, `refreshToken`, `expiresIn`.
- `/discover` users are snake_case (`looking_for`, `is_online`, …).

---

### Task 1: `User.fromJson` dual-casing read

**Files:**
- Modify: `lib/models/user.dart:95-130` (the `return User(...)` block in `fromJson`)
- Test: `test/models/user_casing_test.dart` (create)

**Interfaces:**
- Consumes: nothing new.
- Produces: `User.fromJson(Map<String, dynamic>)` now populates `lookingFor`, `isOnline`,
  `isVerified`, `lastActive`, `createdAt`, and all five preference fields from **either**
  snake_case or camelCase keys. No signature change.

- [ ] **Step 1: Write the failing test**

Create `test/models/user_casing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';

// Mirrors the live prod GET /users/me shape (camelCase).
Map<String, dynamic> _camelPayload() => {
      'id': 'u1',
      'email': 'a@b.com',
      'name': 'Ann',
      'age': 27,
      'bio': 'hi',
      'photos': <dynamic>[],
      'location': null,
      'interests': <dynamic>[],
      'gender': 'female',
      'lookingFor': 'male',
      'isOnline': true,
      'isVerified': true,
      'lastActive': '2026-07-20T10:00:00.000Z',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'preferences': {
        'minAge': 21,
        'maxAge': 40,
        'maxDistance': 25,
        'showDistance': false,
        'showOnlineStatus': false,
      },
    };

// Mirrors the /discover shape (snake_case).
Map<String, dynamic> _snakePayload() => {
      'id': 'u2',
      'name': 'Bo',
      'age': 30,
      'bio': 'yo',
      'photos': <dynamic>[],
      'interests': <dynamic>[],
      'gender': 'male',
      'looking_for': 'female',
      'is_online': true,
      'is_verified': true,
      'last_active': '2026-07-20T10:00:00.000Z',
      'created_at': '2026-01-01T00:00:00.000Z',
      'preferences': {
        'min_age': 22,
        'max_age': 45,
        'max_distance': 30,
        'show_distance': false,
        'show_online_status': false,
      },
    };

void main() {
  group('User.fromJson camelCase (/users/me, /auth/*)', () {
    test('parses lookingFor / isOnline / isVerified / dates', () {
      final u = User.fromJson(_camelPayload());
      expect(u.lookingFor, Gender.male);
      expect(u.isOnline, isTrue);
      expect(u.isVerified, isTrue);
      expect(u.createdAt, isNotNull);
      expect(u.lastActive.year, 2026);
    });

    test('parses camelCase preferences', () {
      final u = User.fromJson(_camelPayload());
      expect(u.minAgePreference, 21);
      expect(u.maxAgePreference, 40);
      expect(u.maxDistancePreference, 25);
      expect(u.showDistance, isFalse);
      expect(u.showOnlineStatus, isFalse);
    });
  });

  group('User.fromJson snake_case (/discover) still works', () {
    test('parses looking_for / is_online and snake preferences', () {
      final u = User.fromJson(_snakePayload());
      expect(u.lookingFor, Gender.female);
      expect(u.isOnline, isTrue);
      expect(u.minAgePreference, 22);
      expect(u.maxDistancePreference, 30);
      expect(u.showOnlineStatus, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/user_casing_test.dart`
Expected: FAIL — camelCase group fails (`lookingFor` → `Gender.other`, `minAgePreference` → 18, etc.) because `fromJson` reads snake_case keys only.

- [ ] **Step 3: Write minimal implementation**

In `lib/models/user.dart`, edit the `return User(...)` block inside `fromJson` (lines 95-130). Add a camelCase fallback to each mismatched key. The `preferences` map already exists (line 93); read both casings from it:

```dart
      lookingFor: _parseGender(json['looking_for'] ?? json['lookingFor']),
      minAgePreference: preferences['min_age'] ?? preferences['minAge'] ?? 18,
      maxAgePreference: preferences['max_age'] ?? preferences['maxAge'] ?? 50,
      maxDistancePreference:
          (preferences['max_distance'] ?? preferences['maxDistance'] ?? 50)
              .toDouble(),
      showDistance:
          preferences['show_distance'] ?? preferences['showDistance'] ?? true,
      showOnlineStatus: preferences['show_online_status'] ??
          preferences['showOnlineStatus'] ??
          true,
      lastActive: (json['last_active'] ?? json['lastActive']) != null
          ? DateTime.parse(json['last_active'] ?? json['lastActive'])
          : DateTime.now(),
      isOnline: json['is_online'] ?? json['isOnline'] ?? false,
      isVerified: json['is_verified'] ?? json['isVerified'] ?? false,
      createdAt: (json['created_at'] ?? json['createdAt']) != null
          ? DateTime.parse(json['created_at'] ?? json['createdAt'])
          : null,
```

Leave the already-correct lines unchanged (`id`, `email`, `name`, `age`, `bio`, `photos`,
`location`, `distance`, `interests`, `gender`, `common_interests`, `is_premium`,
`premium_expires_at`, `super_likes_remaining`, `is_profile_complete`, `preferred_language`).
The backend emits these consistently or they are app-internal.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/user_casing_test.dart`
Expected: PASS (all three groups).

- [ ] **Step 5: Guard against regressions in the wider suite**

Run: `flutter test test/models/`
Expected: PASS — confirms `user_preferred_language_test.dart` and `story_test.dart` still pass.

- [ ] **Step 6: Commit**

```bash
git add lib/models/user.dart test/models/user_casing_test.dart
git commit -m "fix(model): parse User from both camelCase and snake_case payloads

/users/me and /auth/* emit camelCase; /discover emits snake_case, both via
User.fromJson. lookingFor/isOnline/isVerified/dates/preferences now read
either casing (snake first), fixing silent fallback to Gender.other and
default preferences on the real user object."
```

---

### Task 2: `PATCH /users/me` body writes camelCase

**Files:**
- Modify: `lib/services/user_service.dart:33-58` (the `updateProfile` method)
- Test: `test/services/update_profile_body_test.dart` (create)

**Interfaces:**
- Consumes: `Gender.toApiString()` (`lib/models/user.dart:271`).
- Produces: a new pure top-level function
  `Map<String, dynamic> buildUpdateProfileBody({String? name, String? bio, List<String>? interests, Gender? lookingFor, int? age})`
  in `lib/services/user_service.dart`. `UserService.updateProfile` calls it. The body includes
  `lookingFor` (camelCase, what the backend reads) and, for forward-compat with any
  snake_case-reading path, also `looking_for`.

- [ ] **Step 1: Write the failing test**

Create `test/services/update_profile_body_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/user_service.dart';

void main() {
  group('buildUpdateProfileBody', () {
    test('omits null fields', () {
      final body = buildUpdateProfileBody(name: 'Ann');
      expect(body.keys, ['name']);
      expect(body['name'], 'Ann');
    });

    test('writes lookingFor in camelCase (backend read key)', () {
      final body = buildUpdateProfileBody(lookingFor: Gender.male);
      expect(body['lookingFor'], 'male');
    });

    test('also includes snake_case looking_for for forward-compat', () {
      final body = buildUpdateProfileBody(lookingFor: Gender.female);
      expect(body['looking_for'], 'female');
    });

    test('passes through name/bio/interests/age', () {
      final body = buildUpdateProfileBody(
        name: 'Ann',
        bio: 'hi',
        interests: ['a', 'b'],
        age: 29,
      );
      expect(body['name'], 'Ann');
      expect(body['bio'], 'hi');
      expect(body['interests'], ['a', 'b']);
      expect(body['age'], 29);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/update_profile_body_test.dart`
Expected: FAIL — `buildUpdateProfileBody` is undefined.

- [ ] **Step 3: Write minimal implementation**

In `lib/services/user_service.dart`, add a top-level function (outside the class, near the top
of the file after imports):

```dart
/// Builds the PATCH /users/me request body. The flame backend reads camelCase
/// (`lookingFor`); snake_case (`looking_for`) is included for forward-compat.
Map<String, dynamic> buildUpdateProfileBody({
  String? name,
  String? bio,
  List<String>? interests,
  Gender? lookingFor,
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
  if (age != null) body['age'] = age;
  return body;
}
```

Then replace the inline body construction in `updateProfile` (`user_service.dart:39-45`) with a
call to it:

```dart
  Future<ServiceResult<User>> updateProfile({
    String? name,
    String? bio,
    List<String>? interests,
    Gender? lookingFor,
    int? age,
  }) async {
    final body = buildUpdateProfileBody(
      name: name,
      bio: bio,
      interests: interests,
      lookingFor: lookingFor,
      age: age,
    );

    final response = await _apiClient.patch('/users/me', body: body);

    if (response.success && response.data != null) {
      final user = User.fromJson(response.data);
      return ServiceResult.success(user);
    }

    return ServiceResult.failure(response.error ?? 'Failed to update profile');
  }
```

Confirm `Gender` is imported in `user_service.dart` (it already uses `Gender` in the method
signature, so no new import is needed).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/services/update_profile_body_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/services/user_service.dart lib/models/user.dart`
Expected: No new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/services/user_service.dart test/services/update_profile_body_test.dart
git commit -m "fix(profile): send camelCase lookingFor in PATCH /users/me

Backend reads camelCase; the old body sent snake_case looking_for only, so
edits to Looking-For were silently dropped. Body now emits both casings via
the testable buildUpdateProfileBody helper."
```

---

### Task 3: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Run the whole test suite**

Run: `flutter test`
Expected: PASS. If any pre-existing test asserted the old (broken) default behavior — e.g. an
edit-profile widget test expecting "Other" — update that assertion to the corrected value and
note it in the commit.

- [ ] **Step 2: Analyze the project**

Run: `flutter analyze`
Expected: No new issues introduced by this phase.

- [ ] **Step 3: Manual spot-check (optional but recommended)**

Run the app against prod, log in as `demo@flame.app` / `FlameDemo123`, open **My Profile**.
Expected: "Looking for" reflects the real value (`male` for demo), not "Other"; Age Range and
Max Distance reflect real preferences, not the 18–50 / 50 km defaults. Edit Looking-For, save,
reopen — the change persists and does not reset.

- [ ] **Step 4: Commit any test-assertion fixups**

```bash
git add -A
git commit -m "test: update assertions for corrected casing-tolerant parsing"
```

(Skip if Step 1 required no changes.)

---

## Self-Review

**Spec coverage (Phase 2-H):** "Make `User.fromJson` + token parsing dual-tolerant … Confirm
PATCH write casing matches backend."
- `User.fromJson` dual-tolerance → Task 1. ✅
- PATCH write casing → Task 2. ✅
- **Token parsing:** login/register token parse is *already* dual-tolerant
  (`auth_service.dart:39,93`). The only snake_case-only token parses are the **social** methods
  (`auth_service.dart:245,283,319`), and social login is being **hidden** in Phase 1 (spec §5-D).
  To avoid overlapping edits, the social token-parse dual-tolerance is folded into the Phase 1
  plan (where those methods are touched), not duplicated here. Noted so it isn't lost.

**Placeholder scan:** No TBD/TODO/"handle edge cases" — every code step is concrete. ✅

**Type consistency:** `buildUpdateProfileBody` signature is identical in Task 2's interface
block, implementation, and test. `Gender.toApiString()` and `_parseGender` match `user.dart`.
Preference field names (`minAgePreference`, `maxDistancePreference`, `showDistance`,
`showOnlineStatus`) match the `User` constructor. ✅
