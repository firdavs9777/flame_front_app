# Phase 3 — Profile Photo Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the profile photo menu actually work — implement the "Delete photo" and "Set as main photo" actions (currently TODO stubs that do nothing), wired to the real backend endpoints.

**Architecture:** The delete (`DELETE /users/me/photos/:id`) and reorder (`PATCH /users/me/photos/reorder`) endpoints are real and keyed by **photo id**, but the app currently parses `/users/me` photos into a `List<String>` of URLs and throws the ids away. We carry the ids alongside the URLs with a new index-aligned `User.photoIds` list (zero blast radius — every existing `user.photos` consumer keeps working). New `CurrentUserNotifier` methods perform delete/set-main by id; the edit-profile bottom sheet calls them.

**Tech Stack:** Flutter, Dart, Riverpod, `flutter_test`. No new dependencies.

## Global Constraints

- API base (prod): `https://api.banatalk.com/flamebackend/v1`. Delete = `DELETE /users/me/photos/:id`, reorder = `PATCH /users/me/photos/reorder` with body `{ "photo_ids": [...] }` (both already implemented in `user_service.dart`). Photo upload is separately broken in prod (Spaces) — NOT this plan's concern; delete/reorder of existing photos work.
- `User.photos` stays `List<String>` (URLs). Do NOT change its type or any consumer of it (`profile_card.dart`, `my_profile_screen.dart`, etc.). Add `photoIds` in parallel, index-aligned.
- `User.fromJson` must remain dual-casing tolerant (Phase 2) — do not regress it.
- Commands: `flutter test <path>`, `flutter analyze <paths>`.

**Empirically verified:** `/users/me` returns `photos` as a list of objects `{id, url, is_primary, order}` (parsed by the existing `Photo.fromJson`, `user_service.dart:253`); string-only photo lists are also tolerated by the current parser.

**Deferred (NOT in this plan — tracked for later):**
- Verified badge fix (`profile_card.dart:183`) — that file has unrelated uncommitted working-tree changes; editing it would sweep them into a commit. Defer to when that file is clean.
- Profile-detail like/super-like buttons (`profile_detail_screen.dart`) — the screen is opened from BOTH the discover deck and chat (viewing a match), so wiring like/pass is context-ambiguous and misleading while matching is dead-ended. Defer.
- `PATCH /users/me/preferences` + `/location` endpoint reconciliation — no UI currently calls these; low value now.

---

### Task 1: Carry photo ids on the User model

**Files:**
- Modify: `lib/models/user.dart`
- Test: `test/models/user_photo_ids_test.dart` (create)

**Interfaces:**
- Produces: `User.photoIds` (`List<String>`, default `const []`), index-aligned with `User.photos`.
  `User.fromJson` populates both from the same photo entries (id is `''` when a photo entry is a
  bare URL string). `copyWith` accepts `photoIds`.

- [ ] **Step 1: Write the failing test**

Create `test/models/user_photo_ids_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';

Map<String, dynamic> _base(List photos) => {
      'id': 'u1',
      'name': 'Ann',
      'age': 27,
      'bio': '',
      'interests': <dynamic>[],
      'gender': 'female',
      'photos': photos,
    };

void main() {
  test('fromJson parses photo objects into aligned photos + photoIds', () {
    final u = User.fromJson(_base([
      {'id': 'p1', 'url': 'https://x/1.jpg'},
      {'id': 'p2', 'url': 'https://x/2.jpg'},
    ]));
    expect(u.photos, ['https://x/1.jpg', 'https://x/2.jpg']);
    expect(u.photoIds, ['p1', 'p2']);
  });

  test('bare string photos yield empty ids, still aligned', () {
    final u = User.fromJson(_base(['https://x/a.jpg']));
    expect(u.photos, ['https://x/a.jpg']);
    expect(u.photoIds, ['']);
  });

  test('entries with empty url are dropped from BOTH lists (stay aligned)', () {
    final u = User.fromJson(_base([
      {'id': 'p1', 'url': ''},
      {'id': 'p2', 'url': 'https://x/2.jpg'},
    ]));
    expect(u.photos, ['https://x/2.jpg']);
    expect(u.photoIds, ['p2']);
  });

  test('photoIds defaults to empty list when absent', () {
    final u = User.fromJson(_base(<dynamic>[]));
    expect(u.photoIds, isEmpty);
  });

  test('copyWith replaces photoIds', () {
    final u = User.fromJson(_base(<dynamic>[])).copyWith(
      photos: ['a'],
      photoIds: ['x'],
    );
    expect(u.photoIds, ['x']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/models/user_photo_ids_test.dart`
Expected: FAIL — `photoIds` getter does not exist (compile error).

- [ ] **Step 3: Implement**

In `lib/models/user.dart`:

1. Add the field after `final List<String> photos;`:

```dart
  /// Backend photo ids, index-aligned with [photos]. Empty string for a photo
  /// that arrived as a bare URL (no id). Used for delete/reorder by id.
  final List<String> photoIds;
```

2. Add to the const constructor (after `required this.photos,`):

```dart
    this.photoIds = const [],
```

3. In `fromJson`, replace the `parsePhotos` local function and its use. Replace the existing
   `List<String> parsePhotos(dynamic photos) { ... }` block with a combined parser that fills two
   aligned lists:

```dart
    // Parse photos into aligned URL + id lists. Entries can be bare URL strings
    // or objects {url, id}; entries without a usable URL are dropped from both.
    final photoUrls = <String>[];
    final photoIdList = <String>[];
    final rawPhotos = json['photos'];
    if (rawPhotos is List) {
      for (final p in rawPhotos) {
        String url = '';
        String id = '';
        if (p is String) {
          url = p;
        } else if (p is Map) {
          url = p['url']?.toString() ?? '';
          id = p['id']?.toString() ?? '';
        }
        if (url.isNotEmpty) {
          photoUrls.add(url);
          photoIdList.add(id);
        }
      }
    }
```

4. In the `return User(...)`, change `photos: parsePhotos(json['photos']),` to:

```dart
      photos: photoUrls,
      photoIds: photoIdList,
```

5. Add `photoIds` to `copyWith`: add the parameter `List<String>? photoIds,` and the line
   `photoIds: photoIds ?? this.photoIds,`.

Do NOT add `photoIds` to `toJson` (client-only state; keeps PATCH bodies unchanged). Leave the
Phase-2 dual-casing fallbacks intact.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/models/user_photo_ids_test.dart`
Expected: PASS.

- [ ] **Step 5: Guard the model suite**

Run: `flutter test test/models/`
Expected: PASS — `user_casing_test.dart`, `user_preferred_language_test.dart`, `story_test.dart`
still green.

- [ ] **Step 6: Commit**

```bash
git add lib/models/user.dart test/models/user_photo_ids_test.dart
git commit -m "feat(profile): carry backend photo ids on User (index-aligned photoIds)

/users/me returns photo objects with ids; the parser kept only URLs. Adds
User.photoIds aligned with photos so delete/reorder-by-id become possible,
without changing the photos List<String> type or any consumer."
```

---

### Task 2: Delete + set-main provider methods

**Files:**
- Modify: `lib/providers/user_provider.dart`
- Test: `test/providers/photo_management_test.dart` (create)

**Interfaces:**
- Consumes: `User.photoIds` (Task 1); `UserService.deletePhoto(String)`,
  `UserService.reorderPhotos(List<String>)` (both exist, `user_service.dart:176,187`).
- Produces on `CurrentUserNotifier`:
  - `Future<bool> deletePhotoAt(int index)` — deletes by `photoIds[index]`; on success removes that
    index from both `photos` and `photoIds` in state. Returns false if no current user, index out
    of range, or the id is empty/unknown.
  - `Future<bool> setMainPhotoAt(int index)` — reorders so `photoIds[index]` is first via
    `reorderPhotos`; on success updates state from the returned photo list. Returns false on the
    same guards.
  - `uploadPhoto` now also appends the uploaded photo's id to `photoIds`.

- [ ] **Step 1: Write the failing test**

Create `test/providers/photo_management_test.dart`. Inject a fake `UserService` by subclassing it
and overriding only the methods used:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/providers/user_provider.dart';

class _FakeUserService extends UserService {
  bool deleteCalled = false;
  String? deletedId;
  List<String>? reorderedIds;

  @override
  Future<ServiceResult<void>> deletePhoto(String photoId) async {
    deleteCalled = true;
    deletedId = photoId;
    return ServiceResult.success(null);
  }

  @override
  Future<ServiceResult<List<Photo>>> reorderPhotos(List<String> photoIds) async {
    reorderedIds = photoIds;
    // Echo back the requested order as Photo objects.
    final photos = <Photo>[];
    for (var i = 0; i < photoIds.length; i++) {
      photos.add(Photo(id: photoIds[i], url: 'url-${photoIds[i]}', order: i));
    }
    return ServiceResult.success(photos);
  }
}

User _userWithPhotos() => User.fromJson({
      'id': 'u1',
      'name': 'Ann',
      'age': 27,
      'bio': '',
      'interests': <dynamic>[],
      'gender': 'female',
      'photos': [
        {'id': 'p1', 'url': 'url-p1'},
        {'id': 'p2', 'url': 'url-p2'},
        {'id': 'p3', 'url': 'url-p3'},
      ],
    });

void main() {
  test('deletePhotoAt removes the photo + id at that index on success', () async {
    final fake = _FakeUserService();
    final n = CurrentUserNotifier(fake)..setUser(_userWithPhotos());

    final ok = await n.deletePhotoAt(1);

    expect(ok, isTrue);
    expect(fake.deletedId, 'p2');
    expect(n.state.value!.photoIds, ['p1', 'p3']);
    expect(n.state.value!.photos, ['url-p1', 'url-p3']);
  });

  test('deletePhotoAt returns false for an unknown/empty id', () async {
    final fake = _FakeUserService();
    final u = User.fromJson({
      'id': 'u1', 'name': 'A', 'age': 20, 'bio': '', 'interests': [],
      'gender': 'female', 'photos': ['bare-url'], // id == ''
    });
    final n = CurrentUserNotifier(fake)..setUser(u);

    final ok = await n.deletePhotoAt(0);

    expect(ok, isFalse);
    expect(fake.deleteCalled, isFalse);
  });

  test('setMainPhotoAt reorders selected id to the front', () async {
    final fake = _FakeUserService();
    final n = CurrentUserNotifier(fake)..setUser(_userWithPhotos());

    final ok = await n.setMainPhotoAt(2);

    expect(ok, isTrue);
    expect(fake.reorderedIds, ['p3', 'p1', 'p2']);
    expect(n.state.value!.photoIds, ['p3', 'p1', 'p2']);
    expect(n.state.value!.photos, ['url-p3', 'url-p1', 'url-p2']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/photo_management_test.dart`
Expected: FAIL — `deletePhotoAt` / `setMainPhotoAt` do not exist.

- [ ] **Step 3: Implement**

In `lib/providers/user_provider.dart`:

1. Update `uploadPhoto` success branch (lines 100-102) to also track the id:

```dart
      state = AsyncValue.data(currentUser.copyWith(
        photos: [...currentUser.photos, result.data!.url],
        photoIds: [...currentUser.photoIds, result.data!.id],
      ));
```

2. Add two methods to `CurrentUserNotifier` (e.g. after `deletePhoto`):

```dart
  /// Deletes the photo at [index] by its backend id and updates local state.
  Future<bool> deletePhotoAt(int index) async {
    final currentUser = state.valueOrNull;
    if (currentUser == null) return false;
    if (index < 0 || index >= currentUser.photoIds.length) return false;
    final photoId = currentUser.photoIds[index];
    if (photoId.isEmpty) return false;

    final result = await _userService.deletePhoto(photoId);
    if (!result.success) return false;

    final photos = [...currentUser.photos]..removeAt(index);
    final ids = [...currentUser.photoIds]..removeAt(index);
    state = AsyncValue.data(currentUser.copyWith(photos: photos, photoIds: ids));
    return true;
  }

  /// Makes the photo at [index] the main photo by reordering it to the front.
  Future<bool> setMainPhotoAt(int index) async {
    final currentUser = state.valueOrNull;
    if (currentUser == null) return false;
    if (index <= 0 || index >= currentUser.photoIds.length) return false;
    final id = currentUser.photoIds[index];
    if (id.isEmpty) return false;

    final ids = [...currentUser.photoIds];
    ids.removeAt(index);
    ids.insert(0, id);

    final result = await _userService.reorderPhotos(ids);
    if (!result.success || result.data == null) return false;

    final photos = result.data!;
    state = AsyncValue.data(currentUser.copyWith(
      photos: photos.map((p) => p.url).toList(),
      photoIds: photos.map((p) => p.id).toList(),
    ));
    return true;
  }
```

Note `setMainPhotoAt` guards `index <= 0` (index 0 is already main; nothing to do).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/photo_management_test.dart`
Expected: PASS (all three).

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/providers/user_provider.dart lib/models/user.dart`
Expected: No new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/user_provider.dart test/providers/photo_management_test.dart
git commit -m "feat(profile): delete + set-main photo provider methods

deletePhotoAt/setMainPhotoAt operate by backend photo id (from photoIds),
update local state on success, and no-op safely on unknown ids. uploadPhoto
now also records the new photo's id."
```

---

### Task 3: Wire the edit-profile photo menu

**Files:**
- Modify: `lib/screens/profile/edit_profile_screen.dart` (`_showPhotoOptions`, lines 299-327)

**Interfaces:**
- Consumes: `currentUserProvider.notifier.deletePhotoAt(int)` / `setMainPhotoAt(int)` (Task 2).

- [ ] **Step 1: Implement**

In `lib/screens/profile/edit_profile_screen.dart`, replace the two `// TODO` bodies in
`_showPhotoOptions` (lines 310-321). The "Set as main photo" `onTap`:

```dart
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await ref
                      .read(currentUserProvider.notifier)
                      .setMainPhotoAt(index);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok
                          ? 'Main photo updated'
                          : 'Could not update main photo'),
                    ),
                  );
                },
```

The "Delete photo" `onTap`:

```dart
              onTap: () async {
                Navigator.pop(context);
                final ok = await ref
                    .read(currentUserProvider.notifier)
                    .deletePhotoAt(index);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Photo deleted' : 'Could not delete photo'),
                  ),
                );
              },
```

Confirm the enclosing widget is a `ConsumerState` (it already uses `ref` elsewhere, e.g.
`_uploadPhoto` at line 382, so `ref` and `mounted` are in scope). The `index` parameter is
already provided to `_showPhotoOptions(int index)`.

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/screens/profile/edit_profile_screen.dart`
Expected: No new issues (no `use_build_context_synchronously` — the `if (!mounted) return;` guards
the async gap before using `context`).

- [ ] **Step 3: Commit**

```bash
git add lib/screens/profile/edit_profile_screen.dart
git commit -m "feat(profile): wire delete + set-main photo menu actions

Replaces the two TODO stubs in the edit-profile photo sheet with real calls
to deletePhotoAt / setMainPhotoAt, with success/failure feedback."
```

---

### Task 4: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Full test suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 2: Analyze the project**

Run: `flutter analyze`
Expected: No NEW issues in the files this phase touched (`user.dart`, `user_provider.dart`,
`edit_profile_screen.dart`, and the new tests). Pre-existing unrelated lints are acceptable.

- [ ] **Step 3: Commit any fixups**

```bash
git add -A && git commit -m "test: fixups for phase-3 photo management"
```

(Skip if Step 1/2 required no changes. If committing, stage ONLY files this phase touched — the
working tree has unrelated uncommitted user changes.)

---

## Self-Review

**Spec coverage (Phase 3, spec §5-I):** photo delete + set-as-main + capture Photo.id →
Tasks 1-3. ✅ Items J (detail buttons) and K (badge, preferences/location) are explicitly deferred
with reasons in the "Deferred" note above (collision / context-ambiguity / no-caller). ✅

**Placeholder scan:** No TBD/TODO/"handle edge cases" — the plan REMOVES two TODO stubs and every
step has concrete code. ✅

**Type consistency:** `photoIds` is `List<String>` everywhere (model field, copyWith, provider
methods, tests). `deletePhotoAt(int)` / `setMainPhotoAt(int)` signatures match across Task 2's
interface, implementation, tests, and Task 3's call sites. `reorderPhotos(List<String>) ->
ServiceResult<List<Photo>>` and `Photo(id,url,order)` match `user_service.dart`. ✅
