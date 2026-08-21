# Scope B — Profile, Settings, Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three tabs instead of four, one owner for every preference, two dead controls made real, and Profile plus Settings localised, themed and responsive.

**Architecture:** Settings moves behind a gear in Profile so the bar carries only surfaces users live in. The Discover filter sheet becomes the single editor for discovery preferences and Edit Profile drops its duplicate section. Like/super-like wire to the existing `swipeProvider`, photo reorder gets the route it never had, and Settings' twenty ad-hoc rows collapse into one section/row widget pair.

**Tech Stack:** Flutter 3.38.x, Riverpod, `intl`. Backend: Node, Express, Mongoose, `node:test` + `supertest`.

**Spec:** `docs/superpowers/specs/2026-08-21-profile-settings-nav-design.md`

## Global Constraints

- **Two repositories.** App: `/Users/davis/Desktop/Personal/flame`, branch `feat/profile-settings-nav`. Backend: `/Users/davis/Desktop/Personal/language_exchange_backend_application`, branch `main`. Commit separately.
- **The backend auto-deploys on push to `main`** via `.github/workflows/deploy.yml` (SSH to DigitalOcean, `git reset --hard origin/main`, `npm ci`, PM2 restart). A backend push is a production deploy. Do not push the backend until its tests are green.
- **App gate:** `flutter analyze` at **0 errors, 0 warnings** and `flutter test` fully green, before every commit.
- **Backend gate:** `node --test flame/__tests__/<file>.test.js` from the repo root, green. The suite has a known flake under back-to-back runs — re-run any failure individually before treating it as real.
- **Every new user-facing string** goes in `lib/l10n/app_en.arb` **and all 12 sibling ARBs**. `test/l10n/arb_parity_test.dart` fails on a missing key.
- **No new colour literals.** Tokens from `lib/theme/app_tokens.dart`, or a named `AppColors` constant when the colour genuinely does not vary by theme.
- **Photo JSON is snake_case on the wire.** The client's `Photo.fromJson` reads `id`, `url`, `is_primary`, `order`. The existing upload route returns camelCase `isPrimary`, so that field already parses as `false` on every photo — see Task 5, which emits both casings rather than propagating the bug.
- **App test fakes:** subclass and override. Build models with `User.fromJson({...})`. Widget hosts need `AppLocalizations.localizationsDelegates` — several existing hosts had to gain it in Scope A for the same reason.
- **Backend test harness:** one in-memory Mongo per file, fresh app per test. Copy the harness from `flame/__tests__/authRateLimit.test.js`. Require models **lazily inside helpers**, never at file top level, or writes buffer against a closed connection.

---

## File Structure

**Backend — modify:**
- `flame/routes/users.js` — the reorder route + schema
- `flame/controllers/userController.js` — `reorderPhotos`
- `flame/services/userService.js` — `reorderPhotos`, and a shared photo serialiser

**Backend — create:**
- `flame/__tests__/photoReorder.test.js`

**App — create:**
- `lib/screens/settings/widgets/settings_section.dart` — `SettingsSection`, `SettingsRow`
- `lib/screens/settings/widgets/settings_snackbar.dart`
- `lib/screens/profile/widgets/photo_picker_sheet.dart` — shared with my-profile
- `lib/screens/profile/edit_profile/edit_profile_screen.dart` — composition root
- `lib/screens/profile/edit_profile/about_section.dart`
- `lib/screens/profile/edit_profile/photos_section.dart`
- `lib/screens/profile/edit_profile/interests_section.dart`

**App — modify:**
- `lib/screens/main_shell.dart` — three tabs, index clamp
- `lib/screens/profile/my_profile_screen.dart` — gear, read-only prefs, preview row
- `lib/screens/profile/profile_detail_screen.dart` — real like/super-like, `isPreview`
- `lib/screens/settings/settings_screen.dart` — rows, show-distance, drop Edit Profile row
- `lib/screens/settings/{notification_settings,blocked_users}_screen.dart` — l10n
- `lib/l10n/*.arb` — ~100 keys
- `test/theme/` — gate extension

**App — delete:**
- `lib/screens/profile/edit_profile_screen.dart` (replaced by the directory)

---

## Task 1: Backend — the photo-reorder route

**Repo:** backend

**Files:**
- Modify: `flame/services/userService.js`
- Modify: `flame/controllers/userController.js:55-60`
- Modify: `flame/routes/users.js:68-80`
- Test: `flame/__tests__/photoReorder.test.js` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `PATCH /users/me/photos/reorder` taking `{ photo_ids: [String] }`, returning `{ success: true, data: { photos: [{ id, url, is_primary, isPrimary, order }] } }`. `userService.reorderPhotos(userId, photoIds)` returns the serialised array.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/photoReorder.test.js`. Copy the harness block from
`flame/__tests__/authRateLimit.test.js` (`MODULES`, `startDb`, `stopDb`,
`freshApp`, `before`/`after`), then:

```js
const P = '/flamebackend/v1';
const authH = (token) => ({ Authorization: `Bearer ${token}` });

async function makeUser(app, email) {
  const res = await request(app).post(`${P}/auth/register`).send({
    email, password: 'Hunter2!!', name: email.split('@')[0].slice(0, 20).padEnd(2, 'x'),
    age: 30, gender: 'female', lookingFor: 'male', interests: ['Travel'],
  }).expect(201);
  return { id: res.body.data.user.id, token: res.body.data.tokens.accessToken };
}

/// Writes photos straight onto the document — the upload route needs a real
/// multipart body and S3, and this route's behaviour does not depend on either.
async function givePhotos(userId, ids) {
  const User = require('../models/User');   // lazily: see Global Constraints
  await User.updateOne({ _id: userId }, {
    $set: {
      photos: ids.map((id, i) => ({
        id, url: `https://stub.example.com/${id}.jpg`,
        isPrimary: i === 0, order: i,
      })),
    },
  });
}

const idsOf = (res) => res.body.data.photos.map((p) => p.id);

test('a permutation reorders and moves isPrimary to the new first', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'reorder-ok@x.com');
  await givePhotos(me.id, ['a', 'b', 'c']);

  const res = await request(app).patch(`${P}/users/me/photos/reorder`)
    .set(authH(me.token)).send({ photo_ids: ['c', 'a', 'b'] }).expect(200);

  assert.deepEqual(idsOf(res), ['c', 'a', 'b']);
  assert.equal(res.body.data.photos[0].is_primary, true);
  assert.equal(res.body.data.photos[1].is_primary, false);
  assert.deepEqual(res.body.data.photos.map((p) => p.order), [0, 1, 2]);
});

test('the response carries is_primary, which is what the client reads', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'reorder-casing@x.com');
  await givePhotos(me.id, ['a', 'b']);

  const res = await request(app).patch(`${P}/users/me/photos/reorder`)
    .set(authH(me.token)).send({ photo_ids: ['b', 'a'] }).expect(200);

  // Photo.fromJson reads is_primary. The upload route emits only isPrimary, so
  // that field parses as false on every photo today; this route emits both.
  assert.equal(res.body.data.photos[0].is_primary, true);
  assert.equal(res.body.data.photos[0].isPrimary, true);
});

test('an id the caller does not own is rejected', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'reorder-foreign@x.com');
  await givePhotos(me.id, ['a', 'b']);

  await request(app).patch(`${P}/users/me/photos/reorder`)
    .set(authH(me.token)).send({ photo_ids: ['a', 'somebody-elses'] }).expect(422);
});

test('a subset is rejected rather than silently deleting a photo', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'reorder-subset@x.com');
  await givePhotos(me.id, ['a', 'b', 'c']);

  await request(app).patch(`${P}/users/me/photos/reorder`)
    .set(authH(me.token)).send({ photo_ids: ['b', 'a'] }).expect(422);

  // And nothing was written.
  const after = await request(app).get(`${P}/users/me`).set(authH(me.token)).expect(200);
  assert.equal(after.body.data.photos.length, 3);
});

test('a duplicated id is rejected', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'reorder-dup@x.com');
  await givePhotos(me.id, ['a', 'b']);

  await request(app).patch(`${P}/users/me/photos/reorder`)
    .set(authH(me.token)).send({ photo_ids: ['a', 'a'] }).expect(422);
});

test('an empty list is rejected', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'reorder-empty@x.com');
  await givePhotos(me.id, ['a']);

  await request(app).patch(`${P}/users/me/photos/reorder`)
    .set(authH(me.token)).send({ photo_ids: [] }).expect(422);
});

test('reordering requires auth', async () => {
  const app = freshApp();
  await request(app).patch(`${P}/users/me/photos/reorder`)
    .send({ photo_ids: ['a'] }).expect(401);
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /Users/davis/Desktop/Personal/language_exchange_backend_application
node --test flame/__tests__/photoReorder.test.js
```
Expected: FAIL — the route returns 404.

- [ ] **Step 3: Add a shared photo serialiser and the service method**

In `flame/services/userService.js`:

```js
/**
 * Wire shape for a photo.
 *
 * Both casings on purpose. The Flutter client's Photo.fromJson reads
 * `is_primary`, while uploadPhoto has always returned the raw subdocument with
 * `isPrimary` — so that field currently parses as false on every photo. Emitting
 * both fixes this route without changing what installed clients already parse.
 */
function toPhoto(p) {
  return {
    id: p.id,
    url: p.url,
    is_primary: !!p.isPrimary,
    isPrimary: !!p.isPrimary,
    order: p.order,
  };
}

/**
 * Reorders the caller's photos. `photoIds` must be a PERMUTATION of what they
 * currently have — same members, same count, no duplicates.
 *
 * Not a subset: accepting one would silently delete the omitted photos, which is
 * a destructive outcome for a request whose name is "reorder". Not a superset
 * either, since an id the caller does not own is either someone else's photo or
 * a typo, and neither should write.
 */
async function reorderPhotos(userId, photoIds) {
  const user = await User.findById(userId);
  if (!user || user.isDeleted) throw new NotFoundError('User not found');

  const current = user.photos || [];
  if (!Array.isArray(photoIds) || photoIds.length === 0) {
    throw new ValidationError('photo_ids must be a non-empty list');
  }
  if (new Set(photoIds).size !== photoIds.length) {
    throw new ValidationError('photo_ids must not contain duplicates');
  }
  if (photoIds.length !== current.length) {
    throw new ValidationError(
      'photo_ids must list every photo exactly once');
  }
  const owned = new Set(current.map((p) => p.id));
  for (const id of photoIds) {
    if (!owned.has(id)) throw new ValidationError(`unknown photo id: ${id}`);
  }

  const byId = new Map(current.map((p) => [p.id, p]));
  user.photos = photoIds.map((id, index) => {
    const photo = byId.get(id);
    photo.order = index;
    // The first photo is the primary one, by definition of the ordering.
    photo.isPrimary = index === 0;
    return photo;
  });

  await user.save({ validateModifiedOnly: true });
  return user.photos.map(toPhoto);
}
```

Add `reorderPhotos` and `toPhoto` to the module's exports. Import
`ValidationError` if the file does not already.

- [ ] **Step 4: Add the controller and route**

`flame/controllers/userController.js`:

```js
async function reorderPhotos(req, res) {
  const photos = await userService.reorderPhotos(req.user.id, req.body.photo_ids);
  res.json({ success: true, data: { photos } });
}
```

Add it to `module.exports`.

`flame/routes/users.js`, beside the other `/me/photos` routes (which are mounted
before `/:id` for the reason the existing comment gives):

```js
const reorderSchema = z.object({
  photo_ids: z.array(z.string().min(1)).min(1).max(9),
});

router.patch('/me/photos/reorder', auth, validate.body(reorderSchema),
  asyncHandler(ctrl.reorderPhotos));
```

Nine matches `MAX_PHOTOS_PER_USER` in `userService.js`.

- [ ] **Step 5: Run tests to verify they pass**

```bash
node --test flame/__tests__/photoReorder.test.js
node --test flame/__tests__/users.test.js
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add flame/services/userService.js flame/controllers/userController.js \
        flame/routes/users.js flame/__tests__/photoReorder.test.js
git commit -m "feat(photos): the reorder route the app has always called

CurrentUserNotifier.setMainPhotoAt and UserService.reorderPhotos both existed and
PATCH /users/me/photos/reorder did not, so 'Set as main photo' was removed rather
than fixed.

photo_ids must be a permutation: same members, same count, no duplicates. A subset
would silently delete the omitted photos, which is destructive for a request called
'reorder'; an unknown id is either someone else's photo or a typo, and neither
should write. All four rejections are 422 and write nothing.

The response emits both is_primary and isPrimary. The client's Photo.fromJson reads
is_primary while uploadPhoto has always returned the raw subdocument with
isPrimary — so that field parses as false on every photo today. This route does not
propagate that."
```

---

## Task 2: App — Settings row widgets

**Files:**
- Create: `lib/screens/settings/widgets/settings_section.dart`
- Create: `lib/screens/settings/widgets/settings_snackbar.dart`
- Test: `test/screens/settings/settings_section_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces:

```dart
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required String title, required List<Widget> children});
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required String title, String? subtitle,
      Widget? leading, Widget? trailing, VoidCallback? onTap});
}

enum SettingsSnackBarType { info, error }
void showSettingsSnackBar(BuildContext context, {required String message,
    SettingsSnackBarType type = SettingsSnackBarType.info});
```

- [ ] **Step 1: Write the failing test**

Create `test/screens/settings/settings_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/screens/settings/widgets/settings_section.dart';

Future<void> pump(WidgetTester tester, Widget child,
    {double textScale = 1.0, Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a section shows its title and children', (tester) async {
    await pump(tester, const SettingsSection(
      title: 'Account',
      children: [SettingsRow(title: 'Email')],
    ));

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('a row with onTap is tappable and reports it', (tester) async {
    var taps = 0;
    await pump(tester, SettingsSection(
      title: 'Account',
      children: [SettingsRow(title: 'Email', onTap: () => taps++)],
    ));

    await tester.tap(find.text('Email'));
    expect(taps, 1);
  });

  testWidgets('a row without onTap is not tappable', (tester) async {
    await pump(tester, const SettingsSection(
      title: 'Account',
      children: [SettingsRow(title: 'Email')],
    ));

    // A row that looks tappable but is not is the same class of lie as a dead
    // button, so InkWell must be absent rather than present-with-null.
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('a long title wraps at 2x text scale without overflow',
      (tester) async {
    await pump(tester, const SettingsSection(
      title: 'Privacy',
      children: [
        SettingsRow(
          title: 'Show my approximate distance to other people nearby',
          subtitle: 'Others can see roughly how far away you are',
          trailing: Icon(Icons.chevron_right),
        ),
      ],
    ), textScale: 2.0);

    expect(tester.takeException(), isNull);
  });

  testWidgets('rows are constrained on a wide window', (tester) async {
    await pump(tester, const SettingsSection(
      title: 'Account',
      children: [SettingsRow(title: 'Email', key: ValueKey('row'))],
    ), size: const Size(1200, 900));

    expect(tester.getSize(find.byKey(const ValueKey('row'))).width,
        lessThanOrEqualTo(kSheetMaxWidth));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/settings/settings_section_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Write the widgets**

Create `lib/screens/settings/widgets/settings_section.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:flame/core/layout/breakpoints.dart';
import 'package:flame/theme/app_tokens.dart';

/// A titled group of [SettingsRow]s.
///
/// settings_screen built twenty rows through three private helpers. One widget
/// pair means text scaling, tap targets and width constraints are decided once
/// instead of twenty times.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kSheetMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  color: context.secondaryText,
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// One settings row.
///
/// [onTap] null means genuinely not tappable — no InkWell is built at all, so a
/// row cannot look interactive while doing nothing.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // No fixed height: a large system font must grow the row, not clip it.
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 16)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 16, color: context.onSurface),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: TextStyle(fontSize: 13, color: context.secondaryText),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );

    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}
```

Create `lib/screens/settings/widgets/settings_snackbar.dart`, mirroring
`lib/screens/chat/widgets/chat_snackbar.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:flame/theme/app_theme.dart';

enum SettingsSnackBarType { info, error }

/// One place Settings and Profile report a transient outcome, so error styling
/// is decided once. Mirrors chat_snackbar, following
/// bananatalk_app/lib/pages/settings/widgets/settings_snackbar.dart.
void showSettingsSnackBar(
  BuildContext context, {
  required String message,
  SettingsSnackBarType type = SettingsSnackBarType.info,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor:
          type == SettingsSnackBarType.error ? AppTheme.errorColor : null,
    ),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/settings/settings_section_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify and commit**

```bash
flutter analyze
flutter test
git add lib/screens/settings/widgets/ test/screens/settings/settings_section_test.dart
git commit -m "feat(settings): one section and row widget instead of twenty ad-hoc ones

settings_screen built its rows through three private helpers called twenty times.
One widget pair means text scaling, tap targets and the wide-window constraint are
decided once.

A row with no onTap builds no InkWell at all, rather than an InkWell with a null
callback — a row that looks tappable and is not is the same class of lie as a dead
button.

settings_snackbar mirrors chat_snackbar so each surface has one place that reports
a transient outcome."
```

---

## Task 3: App — three tabs

**Files:**
- Modify: `lib/screens/main_shell.dart:28-34`
- Modify: `lib/screens/profile/my_profile_screen.dart:39-50`
- Test: `test/screens/main_shell_tabs_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `_MainShellState._screens` is Discover, [Chat], Profile. Settings is reachable via `Navigator.push` from My Profile's app bar.

- [ ] **Step 1: Write the failing test**

Create `test/screens/main_shell_tabs_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/config/env.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/screens/main_shell.dart';
import 'package:flame/screens/settings/settings_screen.dart';

Future<void> pumpShell(WidgetTester tester) async {
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: kSupportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const MainShell(),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('Settings is not a tab', (tester) async {
    await pumpShell(tester);

    expect(find.text('Settings'), findsNothing,
        reason: 'a destination visited rarely does not belong beside Discover');
  });

  testWidgets('the bar carries Discover, Chat and Profile', (tester) async {
    await pumpShell(tester);

    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    if (EnvConfig.current.chatEnabled) {
      expect(find.text('Chat'), findsOneWidget);
    }
  });

  testWidgets('a stale nav index beyond the tab count does not throw',
      (tester) async {
    // bottomNavIndexProvider holds a raw int that outlives a release. Removing an
    // IndexedStack child makes an old value point past the end.
    await tester.pumpWidget(ProviderScope(
      overrides: [bottomNavIndexProvider.overrideWith((ref) => 9)],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: kSupportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const MainShell(),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('SettingsScreen is not built by the shell', (tester) async {
    await pumpShell(tester);

    expect(find.byType(SettingsScreen), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/main_shell_tabs_test.dart`
Expected: FAIL — Settings is still a tab and `SettingsScreen` is in the stack.

- [ ] **Step 3: Drop the tab and clamp the index**

In `lib/screens/main_shell.dart`, remove `const SettingsScreen(),` from `_screens`
and delete the Settings block from `_FlameNavBar._buildNavItems`. Then clamp in
`build`:

```dart
    // bottomNavIndexProvider holds a raw int that outlives a release, and this
    // list just got shorter. An index from a previous version would otherwise
    // select the wrong screen or throw inside IndexedStack.
    final rawIndex = ref.watch(bottomNavIndexProvider);
    final currentIndex = rawIndex.clamp(0, _screens.length - 1);
```

Use `currentIndex` for both the `IndexedStack` and the nav bar.

- [ ] **Step 4: Put the gear on My Profile**

In `my_profile_screen.dart`'s `AppBar.actions`, before the existing edit action:

```dart
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.l10n.navSettings,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
```

`navSettings` already exists in the ARBs — it was the tab label.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: analyze clean, tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/main_shell.dart lib/screens/profile/my_profile_screen.dart \
        test/screens/main_shell_tabs_test.dart
git commit -m "feat(nav): three tabs, with Settings behind a gear in Profile

Settings sat beside Discover and Chat — the two surfaces users live in — for a
destination visited rarely, and it carried a row pointing at Edit Profile which is
also reachable from Profile's pencil.

Removing an IndexedStack child shifts every index after it, and
bottomNavIndexProvider holds a raw int that outlives a release. The shell clamps
it, so an index written by the previous version selects the last tab instead of
throwing. Pinned by test."
```

---

## Task 4: App — one owner for discovery preferences

**Files:**
- Modify: `lib/screens/profile/edit_profile_screen.dart` (delete `_PreferencesSection`)
- Modify: `lib/screens/profile/my_profile_screen.dart` (prefs block taps through)
- Modify: `lib/screens/settings/settings_screen.dart` (drop the Edit Profile row)
- Test: `test/screens/profile/preference_ownership_test.dart` (create)

**Interfaces:**
- Consumes: Task 3's navigation.
- Produces: `EditProfileScreen` has three sections — About, Photos, Interests. No preferences editor, no online-status switch.

- [ ] **Step 1: Write the failing test**

Create `test/screens/profile/preference_ownership_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// A source-level test, deliberately.
///
/// The property is "there is exactly one editor for these preferences", which is
/// about where code lives rather than what one widget renders. A widget test
/// would pass while a second editor sat one screen away.
void main() {
  test('edit-profile contains no preferences editor', () {
    final source = File('lib/screens/profile/edit_profile_screen.dart')
        .readAsStringSync();

    expect(source.contains('_PreferencesSection'), isFalse,
        reason: 'the Discover filter sheet owns discovery preferences');
    expect(source.contains('updatePreferences'), isFalse,
        reason: 'including showOnlineStatus, which lives in Settings');
  });

  test('exactly one file writes discovery preferences', () {
    final writers = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      // The provider and service are the plumbing; screens are the editors.
      if (!entity.path.contains('/screens/')) continue;
      if (source.contains('setMaxDistance(') || source.contains('setAgeRange(')) {
        writers.add(entity.path);
      }
    }

    expect(writers, ['lib/screens/discover/discover_filters_screen.dart'],
        reason: 'three surfaces over one truth is what this removes');
  });

  test('settings does not link to edit profile', () {
    final source = File('lib/screens/settings/settings_screen.dart')
        .readAsStringSync();

    expect(source.contains('EditProfileScreen'), isFalse,
        reason: 'Settings is reached FROM Profile, so pointing back is a loop');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/profile/preference_ownership_test.dart`
Expected: FAIL on all three.

- [ ] **Step 3: Delete the preferences section**

In `edit_profile_screen.dart`: delete `_PreferencesSection` and
`_PreferencesSectionState` (from `class _PreferencesSection` to the end of its
state class), remove it from the screen's section list, and delete the
`savePreferences` typedef plus the `updatePreferences` call and its
`showOnlineStatus` parameter. Delete the now-stale comment at the old line 843
explaining why there is no show-distance control — Task 6 adds one.

- [ ] **Step 4: Make My Profile's preferences block tap through**

In `my_profile_screen.dart`, wrap the existing "Discovery Preferences" block:

```dart
          // Read-only. Displaying a value edited elsewhere is not duplication; a
          // second editor is.
          InkWell(
            onTap: () => Navigator.pushNamed(context, '/discover/filters'),
            child: /* the existing preferences block */,
          ),
```

- [ ] **Step 5: Drop the Edit Profile row from Settings**

Remove the `SettingsRow`/list tile whose title is `'Edit Profile'` and its
`EditProfileScreen` import.

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: PASS. Existing `edit_profile_test.dart` cases covering the preferences
section must be deleted, not adapted — the section is gone.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/ test/screens/
git commit -m "refactor(profile): discovery preferences get exactly one editor

They existed in three places. EditProfileScreen edited lookingFor, the age window
and maxDistance; MyProfileScreen displayed them; and Scope A's filter sheet edits
them too — so Scope A widened a duplication the follow-ups doc had already recorded
for online status.

The filter sheet owns them. Edit Profile's Preferences section is deleted along
with its duplicate online-status switch, which is a setting rather than profile
data and already lives in Settings. My Profile keeps a read-only summary that taps
through to the sheet.

The test is source-level on purpose: 'there is exactly one editor' is a property of
where code lives, and a widget test would pass happily while a second editor sat
one screen away.

Settings' Edit Profile row goes too — Settings is reached from Profile now, so
pointing back is a loop."
```

---

## Task 5: App — like and super-like become real

**Files:**
- Modify: `lib/screens/profile/profile_detail_screen.dart:270-292`
- Test: `test/screens/profile/profile_detail_actions_test.dart` (create)

**Interfaces:**
- Consumes: `swipeProvider.like(User) → Future<String?>`, `swipeProvider.superLike(User) → Future<String?>` — null on success, an error string otherwise. **Both already call `discoveryProvider.removeUser` internally** (`swipe_provider.dart:77`), so the screen must not call it again.
- Produces: `ProfileDetailScreen({required User user, bool isPreview = false})`.

- [ ] **Step 1: Write the failing test**

Create `test/screens/profile/profile_detail_actions_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/swipe_provider.dart';
import 'package:flame/screens/profile/profile_detail_screen.dart';

User _user() => User.fromJson({'id': 'u1', 'name': 'Bea', 'photos': <dynamic>[]});

class _RecordingSwipe extends SwipeNotifier {
  _RecordingSwipe(super.ref);

  final List<String> calls = [];
  String? failWith;

  @override
  Future<String?> like(User user) async {
    calls.add('like:${user.id}');
    return failWith;
  }

  @override
  Future<String?> superLike(User user) async {
    calls.add('super:${user.id}');
    return failWith;
  }
}

late _RecordingSwipe swipe;

Future<void> pumpDetail(WidgetTester tester,
    {bool isPreview = false, String? failWith}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      swipeProvider.overrideWith((ref) {
        swipe = _RecordingSwipe(ref)..failWith = failWith;
        return swipe;
      }),
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
      home: ProfileDetailScreen(user: _user(), isPreview: isPreview),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('like calls the swipe provider', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    expect(swipe.calls, ['like:u1']);
  });

  testWidgets('super-like calls the swipe provider', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.byIcon(Icons.star));
    await tester.pumpAndSettle();

    expect(swipe.calls, ['super:u1']);
  });

  testWidgets('a failed like reports and does not pop', (tester) async {
    await pumpDetail(tester, failWith: 'no likes left');

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    expect(find.text('no likes left'), findsOneWidget);
    expect(find.byType(ProfileDetailScreen), findsOneWidget);
  });

  testWidgets('preview hides every action you cannot take on yourself',
      (tester) async {
    await pumpDetail(tester, isPreview: true);

    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing,
        reason: 'you cannot report or block yourself');
  });

  testWidgets('the flag defaults false so existing call sites are unchanged',
      (tester) async {
    await pumpDetail(tester);

    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });
}
```

Check the real icons first with
`grep -n "Icons\." lib/screens/profile/profile_detail_screen.dart | sed -n '1,20p'`
and use those.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/profile/profile_detail_actions_test.dart`
Expected: FAIL — `isPreview` does not exist and the buttons call nothing.

- [ ] **Step 3: Add the flag and wire the actions**

```dart
class ProfileDetailScreen extends ConsumerStatefulWidget {
  const ProfileDetailScreen({
    super.key,
    required this.user,
    this.isPreview = false,
  });

  final User user;

  /// True when the viewer is looking at their own profile as others see it.
  ///
  /// Hides like, super-like and report: none of them are things you can do to
  /// yourself. Defaults false so every existing call site is unchanged.
  final bool isPreview;
```

Replace the two dead bodies:

```dart
  Future<void> _like() async {
    // swipeProvider.like already removes the user from the deck, so this must
    // not do it again — a second removeUser would be a no-op today and a bug the
    // moment that provider changes.
    final error = await ref.read(swipeProvider.notifier).like(widget.user);
    if (!mounted) return;
    if (error != null) {
      showSettingsSnackBar(context,
          message: error, type: SettingsSnackBarType.error);
      return;
    }
    Navigator.pop(context);
  }
```

`_superLike` is identical but calls `superLike`. Gate the action bar and the
report menu on `if (!widget.isPreview)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/profile/profile_detail_screen.dart \
        test/screens/profile/profile_detail_actions_test.dart
git commit -m "feat(profile): like and super-like actually like

Both buttons were tappable with bodies reading '// Handle like' and
'// Handle super like'. They call swipeProvider now — the same notifier the deck
uses, so a like from a profile and a like from a swipe are the same operation.

Deliberately NOT calling discoveryProvider.removeUser: swipeProvider.like already
does that internally, and a second call would be a no-op today and a bug the moment
that provider changes.

isPreview hides like, super-like and report, because none of them are things you can
do to yourself. It defaults false, so every existing call site is untouched."
```

---

## Task 6: App — show-distance toggle and profile preview

**Files:**
- Modify: `lib/screens/settings/settings_screen.dart`
- Modify: `lib/screens/profile/my_profile_screen.dart`
- Modify: `lib/l10n/*.arb`
- Test: `test/screens/settings/show_distance_test.dart` (create)

**Interfaces:**
- Consumes: Task 2's `SettingsRow`, Task 5's `isPreview`.
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

Create `test/screens/settings/show_distance_test.dart`, following the fake-service
pattern in `test/screens/settings/settings_online_status_test.dart` (which already
subclasses `UserService` and overrides `updatePreferences`). Assert:

```dart
  testWidgets('toggling writes showDistance', (tester) async {
    await pumpSettings(tester, showDistance: true);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('show-distance-switch')));
    await tester.pumpAndSettle();

    expect(service.lastShowDistance, isFalse);
  });

  testWidgets('a failed write reverts the switch', (tester) async {
    await pumpSettings(tester, showDistance: true, succeeds: false);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('show-distance-switch')));
    await tester.pumpAndSettle();

    final sw = tester.widget<Switch>(find.byKey(const ValueKey('show-distance-switch')));
    expect(sw.value, isTrue,
        reason: 'a switch that stays flipped after a failed write lies about '
            'server state');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/settings/show_distance_test.dart`
Expected: FAIL — no such switch.

- [ ] **Step 3: Add the ARB keys**

Add to `lib/l10n/app_en.arb` and all 12 siblings, with translations:

```json
"settingsShowDistance": "Show my distance",
"settingsShowDistanceSubtitle": "Others can see roughly how far away you are",
"profilePreview": "Preview my profile",
"profilePreviewSubtitle": "See what a match sees",
"settingsSaveFailed": "Couldn't save that change"
```

Then `flutter gen-l10n`.

- [ ] **Step 4: Add the toggle**

In the Privacy section of `settings_screen.dart`, beside Show Online Status:

```dart
        SettingsRow(
          title: context.l10n.settingsShowDistance,
          subtitle: context.l10n.settingsShowDistanceSubtitle,
          trailing: Switch(
            key: const ValueKey('show-distance-switch'),
            value: user?.showDistance ?? true,
            onChanged: _setShowDistance,
          ),
        ),
```

```dart
  Future<void> _setShowDistance(bool value) async {
    final ok = await ref
        .read(currentUserProvider.notifier)
        .updatePreferences(showDistance: value);
    if (!mounted || ok) return;
    // Revert: the switch reflects server state, not intent.
    setState(() {});
    showSettingsSnackBar(context,
        message: context.l10n.settingsSaveFailed,
        type: SettingsSnackBarType.error);
  }
```

The backend already honours the field — Scope A's `distanceBetween` returns null
when the target has it off.

- [ ] **Step 5: Add the preview row**

In `my_profile_screen.dart`:

```dart
          SettingsRow(
            title: context.l10n.profilePreview,
            subtitle: context.l10n.profilePreviewSubtitle,
            leading: const Icon(Icons.visibility_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileDetailScreen(user: user, isPreview: true),
              ),
            ),
          ),
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/ lib/l10n/ test/screens/settings/show_distance_test.dart
git commit -m "feat(settings): a show-distance toggle, and a profile preview

Scope A made distance real and taught the server to honour preferences.showDistance
but left users no way to exercise it — and left a comment in edit-profile
explaining that the control was deliberately absent because nothing computed a
distance, which stopped being true the same day. This is the other half.

A failed write reverts the switch: one that stays flipped after the server refused
is lying about server state.

Preview opens ProfileDetailScreen on your own user with isPreview, so you see what a
match sees. The cheapest way a user notices their own profile is thin before
concluding the app is broken."
```

---

## Task 7: App — split the edit-profile screen

**Files:**
- Create: `lib/screens/profile/edit_profile/edit_profile_screen.dart`
- Create: `lib/screens/profile/edit_profile/{about,photos,interests}_section.dart`
- Create: `lib/screens/profile/widgets/photo_picker_sheet.dart`
- Delete: `lib/screens/profile/edit_profile_screen.dart`
- Test: `test/screens/profile/edit_profile_test.dart` (update imports)

**Interfaces:**
- Consumes: Task 4's deletions.
- Produces: `EditProfileScreen` at the new path; `AboutSection`, `PhotosSection`, `InterestsSection`; `showPhotoPickerSheet(BuildContext) → Future<ImageSource?>`.

- [ ] **Step 1: Move the file and split it**

```bash
mkdir -p lib/screens/profile/edit_profile lib/screens/profile/widgets
git mv lib/screens/profile/edit_profile_screen.dart \
       lib/screens/profile/edit_profile/edit_profile_screen.dart
```

Move `_AboutSection`/`_AboutSectionState` into `about_section.dart` as public
`AboutSection`; `_PhotosSection` into `photos_section.dart` as `PhotosSection`;
`_InterestsSection` into `interests_section.dart` as `InterestsSection`. The
typedefs at the top of the original file stay in `edit_profile_screen.dart` and
are imported by the sections.

- [ ] **Step 2: Extract the shared picker sheet**

The image-picker bottom sheet and `_uploadPhoto` are near-identical in
`edit_profile` and `my_profile_screen`. Create
`lib/screens/profile/widgets/photo_picker_sheet.dart`:

```dart
/// Asks camera-or-gallery. Returns null when dismissed.
///
/// One copy: this sheet and its upload path existed near-identically in
/// edit-profile and my-profile, and photo reorder would have made it a third.
Future<ImageSource?> showPhotoPickerSheet(BuildContext context) { ... }
```

Point both screens at it.

- [ ] **Step 3: One age validator**

The age validator and its message appear three times verbatim. Keep one in
`about_section.dart`:

```dart
/// Null when [age] is acceptable, else the reason.
///
/// One copy of a rule that appeared three times verbatim, so the three could
/// disagree after any edit.
String? validateAge(int? age, AppLocalizations l10n) { ... }
```

- [ ] **Step 4: Fix imports and run**

```bash
grep -rn "profile/edit_profile_screen.dart" lib/ test/
```

Point every hit at `profile/edit_profile/edit_profile_screen.dart`.

Run: `flutter analyze && flutter test`
Expected: analyze clean, tests PASS.

- [ ] **Step 5: Check the result**

```bash
wc -l lib/screens/profile/edit_profile/*.dart
```
The composition root should be under 200 lines. If a section exceeds ~350, it is
doing more than one thing.

- [ ] **Step 6: Commit**

```bash
git add -A lib/screens/profile/ test/screens/profile/
git commit -m "refactor(profile): one file per edit-profile section

1023 lines became three sections plus a composition root. Three, not four: gender
preference lived inside the Preferences section that Task 4 deleted, so there is no
separate Looking For.

Stated plainly: this is ahead of the follow-ups doc's own trigger, which was a
sixth section. The argument for doing it anyway is that photo reorder lands in the
photos section this scope and each section already saves independently, so they are
genuinely separate units. Following
bananatalk_app/lib/pages/profile/edit_main/sections/, and deliberately not that
app's 1104-line pages/profile/settings.dart.

Two duplications the follow-ups doc recorded are fixed because the code moved
anyway: the picker sheet and _uploadPhoto become one widget, and the age validator
that appeared three times verbatim becomes one function."
```

---

## Task 8: App — photo reorder reaches the UI

**Files:**
- Modify: `lib/screens/profile/edit_profile/photos_section.dart`
- Test: `test/providers/photo_management_test.dart` (extend)

**Interfaces:**
- Consumes: Task 1's route, Task 7's `PhotosSection`.
- Produces: nothing new.

- [ ] **Step 1: Write the failing test**

Extend `test/providers/photo_management_test.dart`:

```dart
  test('setMainPhotoAt moves the chosen photo to the front', () async {
    final notifier = _seeded(photos: ['a.jpg', 'b.jpg', 'c.jpg'],
        photoIds: ['a', 'b', 'c']);

    expect(await notifier.setMainPhotoAt(2), isTrue);

    expect(notifier.state.value!.photoIds, ['c', 'a', 'b']);
  });

  test('setMainPhotoAt on index 0 is a no-op', () async {
    final notifier = _seeded(photos: ['a.jpg'], photoIds: ['a']);

    expect(await notifier.setMainPhotoAt(0), isFalse,
        reason: 'it is already the main photo; a request is not a change');
  });

  test('a failed reorder leaves the order alone', () async {
    final notifier = _seeded(photos: ['a.jpg', 'b.jpg'], photoIds: ['a', 'b'],
        reorderSucceeds: false);

    expect(await notifier.setMainPhotoAt(1), isFalse);
    expect(notifier.state.value!.photoIds, ['a', 'b'],
        reason: 'an optimistic reorder that reverts on the next fetch looks like '
            'the app forgetting');
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/photo_management_test.dart`
Expected: FAIL — the fake service has no `reorderPhotos` override.

- [ ] **Step 3: Restore the menu item**

In `photos_section.dart`, add to each non-primary photo's long-press menu:

```dart
              PopupMenuItem(
                value: 'main',
                child: Text(context.l10n.profileSetMainPhoto),
              ),
```

and on selection call `setMainPhotoAt(index)`, reporting failure through
`showSettingsSnackBar`. Add `profileSetMainPhoto` to all 13 ARBs.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/profile/ lib/l10n/ test/providers/photo_management_test.dart
git commit -m "feat(profile): choosing your main photo works again

The menu item was removed rather than fixed, because every tap 404'd on a route
that did not exist. It exists now, so the item returns.

A failed reorder leaves the local order untouched: an optimistic reorder that
silently reverts on the next fetch looks like the app forgetting what you asked
for."
```

---

## Task 9: App — localise Profile and Settings

**Files:**
- Modify: `lib/screens/profile/**`, `lib/screens/settings/**`
- Modify: `lib/l10n/*.arb`
- Test: `test/l10n/arb_parity_test.dart` (already enforces parity)

**Interfaces:**
- Consumes: Tasks 2–8.
- Produces: nothing new.

- [ ] **Step 1: Enumerate what is left**

```bash
for f in lib/screens/profile/**/*.dart lib/screens/settings/**/*.dart; do
  n=$(grep -coE "'[A-Z][A-Za-z ,.!?']{3,}'" "$f")
  [ "$n" != "0" ] && printf '%-58s %s\n' "$f" "$n"
done
```

Roughly 100 across six files before the earlier tasks; fewer after, since Tasks 4
and 6 removed and added some.

- [ ] **Step 2: Add the keys**

Work one file at a time. Key naming follows the established convention —
`settings*` for Settings, `profile*` for Profile — so
`grep -n '"settings' lib/l10n/app_en.arb` shows the existing shape.

Script the ARB writes with the same Python pattern used in the Scope A plan: read
each ARB as an `OrderedDict`, add missing keys with per-locale translations, write
back with `indent=2` and a trailing newline. English descriptions go only in
`app_en.arb`.

- [ ] **Step 3: Replace the literals**

Each becomes `context.l10n.<key>`. Files needing the extension gain
`import 'package:flame/core/i18n/build_context_ext.dart';`.

- [ ] **Step 4: Regenerate and run**

```bash
flutter gen-l10n
flutter test test/l10n/
flutter analyze && flutter test
```
Expected: parity passes, analyze clean, all tests PASS. Any widget test whose host
lacks `localizationsDelegates` will now fail to build — add them, as Scope A had to.

- [ ] **Step 5: Confirm nothing was missed**

```bash
grep -rnoE "(Text|title|subtitle|label|hintText)\s*[:(]\s*'[A-Z]" \
  lib/screens/profile lib/screens/settings || echo "clean"
```

- [ ] **Step 6: Commit**

```bash
git add lib/screens/profile/ lib/screens/settings/ lib/l10n/ test/
git commit -m "i18n(profile,settings): the last two un-localised surfaces

Profile and Settings were entirely hardcoded English while chat and Discover read
from the ARBs in thirteen languages. Roughly a hundred strings across six files.

Several widget test hosts needed localizations added, since the screens no longer
render raw English."
```

---

## Task 10: App — theme gate and responsive

**Files:**
- Create: `test/theme/profile_settings_gate_test.dart`
- Modify: `test/theme/app_tokens_test.dart`
- Modify: `lib/screens/profile/**`, `lib/screens/settings/**`, `lib/screens/main_shell.dart`
- Test: `test/screens/settings/settings_layout_test.dart` (create)

**Interfaces:**
- Consumes: everything before it.
- Produces: nothing new.

- [ ] **Step 1: Write the failing gate**

Create `test/theme/profile_settings_gate_test.dart`, the same shape as
`test/theme/discover_theme_test.dart`, scanning `lib/screens/profile`,
`lib/screens/settings` and `lib/screens/main_shell.dart` with the wide regex.

- [ ] **Step 2: Run it**

Run: `flutter test test/theme/profile_settings_gate_test.dart`
Expected: FAIL listing ~5 literals — 2 in the edit-profile tree, 3 in
`main_shell.dart`.

- [ ] **Step 3: Replace them**

Same mapping as the chat and Discover sweeps: surfaces → `context.surface`,
primary text → `context.onSurface`, secondary → `context.secondaryText`, fills →
`context.fill`, hairlines → `context.divider`, foreground on primary →
`context.onPrimary`. Expect to drop `const` where `context.*` enters a constant
expression.

- [ ] **Step 4: Add token-resolution assertions**

Append to `test/theme/app_tokens_test.dart` a test asserting, in both themes, that
`surfaceContainerHighest != surface`, `onSurfaceVariant != onSurface`, and
`dividerTheme.color != surfaceContainerHighest` — a `SettingsRow` divider is drawn
against a fill, and the literal gate cannot see a token resolving to the wrong
colour.

- [ ] **Step 5: Add the layout test**

Create `test/screens/settings/settings_layout_test.dart` asserting Settings and My
Profile pump clean at compact (390×844) and expanded (1024×1366) widths, and at
text scale 1.0 and 2.0 — `tester.takeException()` null in all four combinations.

- [ ] **Step 6: Run and commit**

```bash
flutter analyze && flutter test
git add lib/screens/ test/theme/ test/screens/settings/settings_layout_test.dart
git commit -m "style(profile,settings): a gate rather than a sweep

Only five colour literals remained — the profile upgrade already swept these files.
So the work here is the gate: extend it to profile, settings and the shell so the
new section files and row widgets cannot reintroduce literals.

Token-resolution assertions come with it. A SettingsRow divider is drawn against a
fill, and banning literals proves nothing about what the replacement resolves to.

Layout is pinned at two widths and two text scales, which SettingsRow gets once for
all its call sites instead of twenty times."
```

---

## Task 11: Verify the whole surface

**Files:** none modified.

- [ ] **Step 1: App gate**

```bash
cd /Users/davis/Desktop/Personal/flame
flutter analyze && flutter test
```
Expected: 0 errors, 0 warnings; all pass. It was 550 before this plan.

- [ ] **Step 2: Backend gate**

```bash
cd /Users/davis/Desktop/Personal/language_exchange_backend_application
for f in flame/__tests__/*.test.js; do
  n=$(node --test "$f" 2>&1 | grep -E "^ℹ fail" | grep -oE "[0-9]+")
  [ "$n" != "0" ] && echo "FAILED: $f"
done; echo done
```
Re-run any failure individually before treating it as real.

- [ ] **Step 3: Confirm the removals**

```bash
cd /Users/davis/Desktop/Personal/flame
grep -rq "SettingsScreen()" lib/screens/main_shell.dart && echo "STILL A TAB" || echo "tab gone"
grep -rq "_PreferencesSection" lib/ && echo "PREFS EDITOR REMAINS" || echo "prefs editor gone"
grep -rq "Handle like\|Handle super like" lib/ && echo "DEAD BUTTONS REMAIN" || echo "dead buttons gone"
test ! -f lib/screens/profile/edit_profile_screen.dart && echo "old path gone"
wc -l lib/screens/profile/edit_profile/*.dart lib/screens/settings/settings_screen.dart
```

- [ ] **Step 4: Walk it by hand**

```bash
flutter run --dart-define=APP_ENV=local
```

Confirm: three tabs; the gear opens Settings; Settings has no Edit Profile row; My
Profile's preferences block taps through to the filter sheet; like from a profile
removes that card from the deck; set-as-main-photo works; the show-distance toggle
persists across a restart; preview shows no like or report; Settings is readable at
a large system font and on a tablet; both themes look right.

**Scope A never got this walkthrough** — no device was attached. Do both surfaces
in one pass.

- [ ] **Step 5: Report**

State plainly what the walkthrough showed. If it found nothing, say so rather than
inventing a commit.

---

## Self-Review

**Spec coverage.** Three tabs → Task 3. Index clamp → Task 3. Preference ownership
→ Task 4. Online-status de-duplication → Task 4. Edit Profile row removal → Task 4.
File split → Task 7. Shared picker sheet and single age validator → Task 7.
Like/super-like → Task 5. `isPreview` → Tasks 5, 6. Photo-reorder route → Task 1.
Reorder UI → Task 8. Show-distance toggle → Task 6. Preview row → Task 6.
Localization → Task 9 (plus keys added in 6 and 8). `SettingsSection`/`SettingsRow`
and snackbar → Task 2. Theme gate and token assertions → Task 10. Responsive and
text scale → Tasks 2, 10. Error handling table → Tasks 5, 6, 8. Verification →
Task 11.

**Three spec corrections made while writing.**

1. The spec said the detail screen should call `discoveryProvider.removeUser` after
   a like. It must **not** — `swipeProvider.like` already does
   (`swipe_provider.dart:77`). Task 5 says so explicitly, because the redundant
   call would be invisible today and wrong later.
2. The spec said the reorder route should "return the updated user". The client's
   `UserService.reorderPhotos` parses `{photos: [...]}`, so Task 1 returns that
   shape.
3. The spec did not mention that the existing upload route emits camelCase
   `isPrimary` while `Photo.fromJson` reads `is_primary` — so that field parses as
   `false` on every photo today. Task 1 emits both casings rather than propagating
   it, and pins it with a test.

**Placeholder scan.** No TBDs. Task 9 gives a procedure and a naming convention
rather than a hundred literal edits, which is the right altitude for mechanical
work whose inputs a script enumerates; Task 7 names the classes to move rather
than reproducing ~800 lines. Both are bounded by a verification step.

**Type consistency.** `SettingsSection` / `SettingsRow` defined in Task 2, used in
4, 6, 10. `showSettingsSnackBar` defined in Task 2, used in 5, 6, 8.
`ProfileDetailScreen({user, isPreview})` defined in Task 5, used in 6.
`setMainPhotoAt(int)` is the existing name, used in Task 8. `kSheetMaxWidth` comes
from Scope A's `breakpoints.dart`, used in Tasks 2 and 10.
