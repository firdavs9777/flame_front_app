# Scope B — Profile, Settings, and Navigation

Third and last of the three scopes agreed for the pre-release push.

- **A (done, merged)** — Discover and its filters.
- **B (this spec)** — Profile pages, Settings, the tab bar.
- **C (not started)** — Notifications. Blocked on Firebase credentials and
  `firebase_messaging`, which is not yet a dependency.

Spans two repositories: the app (`flame`) and the backend
(`language_exchange_backend_application/flame`).

## Why

**Discovery preferences exist in three places.** `EditProfileScreen` has a
Preferences section editing `lookingFor`, min/max age and `maxDistance`.
`MyProfileScreen` displays the same three. And Scope A's filter sheet now edits
`lookingFor`, `maxDistance` and interests. Three surfaces over one truth — the
same defect the profile follow-ups doc recorded for online status, which Scope A
widened rather than caused.

**Show Online Status is in two places** — `settings_screen.dart:89` and
`edit_profile_screen.dart:1009`. Both are server-backed now, so neither lies, but
two controls over one preference is the shape that produced the original bug.

**Settings occupies a top-level tab.** It sits beside Discover and Chat, the two
surfaces users live in, and it contains a row pointing at Edit Profile — which is
also reachable from My Profile's pencil.

**Two controls still do nothing.** `profile_detail_screen.dart:277,285` are
tappable like and super-like buttons whose bodies are `// Handle super like` and
`// Handle like`.

**Photo reorder is unreachable.** `CurrentUserNotifier.setMainPhotoAt` and
`UserService.reorderPhotos` exist; `PATCH /users/me/photos/reorder` does not, so
the "Set as main photo" menu item was removed rather than fixed.

**Profile and Settings are entirely un-localised** — roughly 100 hardcoded English
strings across six files, in an app whose chat and Discover surfaces now read from
ARBs in thirteen languages.

**`showDistance` has no control.** Scope A made distance real and taught the server
to honour the field, but left no way for a user to exercise it.
`edit_profile_screen.dart:843` still carries a comment explaining that the absence
is deliberate because nothing computes a distance — which stopped being true
yesterday.

## Decisions taken

| Question | Decision |
|---|---|
| Who owns discovery preferences | **The Discover filter sheet.** Edit Profile drops the section; My Profile keeps a read-only summary linking to the sheet. |
| Where Settings lives | **Behind a gear in Profile's app bar.** Three tabs. |
| Show Online Status | **Settings only.** Leaves Edit Profile. |
| The 1023-line edit screen | **One file per section** (three, after Preferences leaves), plus a composition root. Ahead of the follow-ups doc's stated sixth-section trigger — see below. |
| Dead like / super-like | **Implemented**, wired to `swipeProvider`. |
| Photo reorder | **Route added**, methods become reachable. |
| Premium display | **Left dormant.** `toPublic` does not send `isPremium` and `/billing/status` hardcodes `false`, so sending the field would change nothing on screen. Not a lie — a badge that never appears — and making it real is a billing project. |
| Two additions | **Show-distance toggle** and **Preview my profile.** |

## Not in this scope

- Notifications — Scope C.
- The Stories tray, still fabricating stories in the Messages tab.
- Real premium and billing.
- A verification *flow*. `isVerified` is displayed and `authService.toPublic`
  sends it, so display works; there is no way to *become* verified, and building
  one is its own project.
- A likes-you list or profile visitors, whether or not they later earn a tab.
- The 66 MB release bundle and whether `google_mlkit_face_detection` earns its
  place in it.

---

## Navigation

`_FlameNavBar` already builds items dynamically — Chat is conditional on
`chatEnabled` — so removing Settings is a deletion rather than a restructure.
**Three tabs: Discover · Chat · Profile.**

Two consequences that must be handled together, because `IndexedStack` is
positional:

- `_MainShellState._screens` drops `SettingsScreen`, so every index after it
  shifts down by one. `bottomNavIndexProvider` holds a raw int, so a stale value
  from a previous session could select the wrong screen — the shell clamps it to
  the built list's length.
- The Settings nav item goes, and `SettingsScreen` becomes a pushed route from a
  gear in `MyProfileScreen`'s app bar.

The **"Edit Profile" row inside Settings is removed**: arriving from Profile, it
points back where the user came from.

## Ownership moves

**Discovery preferences leave Edit Profile.** The `_PreferencesSection` — looking-for,
min/max age, `maxDistance` — is deleted. The filter sheet from Scope A already
writes all of it.

`MyProfileScreen` keeps its **read-only** "Discovery Preferences" block (looking
for, age range, max distance) and gains a tap target opening
`/discover/filters`. Read-only display of a value edited elsewhere is not
duplication; a second editor is.

**Show Online Status leaves Edit Profile** and stays in Settings. It is a setting,
not profile data.

Net effect on the file: Preferences and the online-status switch together take
`edit_profile_screen.dart` from 1023 lines to roughly 800 before any splitting.

## The edit-profile split

```
lib/screens/profile/edit_profile/
  edit_profile_screen.dart     composition root: typedefs + the section list
  about_section.dart           name, age, bio
  photos_section.dart          upload, delete, reorder, set-main
  interests_section.dart       the shared catalogue
lib/screens/profile/widgets/
  photo_picker_sheet.dart      shared with my_profile_screen
```

**Three sections, not four.** There is no separate Looking For section — gender
preference lives inside `_PreferencesSection`, which the filter sheet now owns and
which is deleted here.

**This split is ahead of the project's own trigger, deliberately.** The follow-ups
doc said to split "if `edit_profile_screen.dart` grows a sixth section"; it has
four and is going to three. The case for splitting anyway is that photo reorder
lands in the photos section this scope, and ~800 lines across three
independently-saving sections is already past the point where the file is
comfortable to work in. The case against is that the recorded standard says wait.
Flagged rather than assumed.

Each section keeps its **own independent save**, which is the property the profile
upgrade deliberately built.

Following `bananatalk_app/lib/pages/profile/edit_main/sections/`, which uses the
same section-per-file shape. Deliberately *not* following that app's
`pages/profile/settings.dart` at 1104 lines alongside a separate `pages/settings/`
directory — that is the Profile/Settings overlap this scope exists to remove.

Two duplications the follow-ups doc recorded, fixed here because the code moves
anyway: the image-picker sheet and `_uploadPhoto` are near-identical in
`edit_profile_screen` and `my_profile_screen` and become one
`photo_picker_sheet.dart`; the age validator appears three times verbatim and
becomes one function.

## The two dormant paths made real

### Like and super-like on profile detail

Both wire to `swipeProvider`, the notifier the deck already calls. On success the
sheet pops **and** `discoveryProvider.removeUser` drops the profile from the deck.

That second half matters: without it a user could like someone from their detail
view and still be shown their card, which would either produce a duplicate swipe
the server rejects or look like the like never registered.

Failure surfaces through `showSettingsSnackBar` and leaves the deck untouched.

### Photo reorder

**Backend:** `PATCH /users/me/photos/reorder` taking `{ photo_ids: [String] }` —
an ordered list. It must:

- reject any id not belonging to the caller (422, not a silent skip);
- reject a list that is not a permutation of the caller's current photo ids —
  a partial list would silently drop photos;
- write `order` per photo and set `isPrimary` on the first;
- return the updated user, so the app does not need a second fetch.

**App:** `CurrentUserNotifier.setMainPhotoAt` and `UserService.reorderPhotos`
already exist and become reachable. The "Set as main photo" menu item returns to
the photos section.

## The two additions

**Show-distance toggle.** A switch in Settings beside Show Online Status, writing
`preferences.showDistance` through the existing `updatePreferences`. The backend
already honours it — Scope A's `distanceBetween` returns null when the target has
it off. The stale comment at `edit_profile_screen.dart:843` explaining the
control's absence is removed with it.

**Preview my profile.** A row in `MyProfileScreen` pushing `ProfileDetailScreen`
with the current user. The screen already exists and already renders a `User`.

One thing to get right: `ProfileDetailScreen` carries like, super-like and
report/block actions. Previewing your own profile must **not** show them — you
cannot like or report yourself. The screen takes an `isPreview` flag that hides
the action bar, defaulting false so every existing call site is unchanged.

## Localization

Roughly 100 hardcoded strings become ARB keys across all 13 locales:

| File | Approx. strings |
|---|---|
| `edit_profile_screen.dart` | 33 |
| `settings_screen.dart` | 28 |
| `my_profile_screen.dart` | 19 |
| `notification_settings_screen.dart` | 11 |
| `blocked_users_screen.dart` | 6 |
| `profile_detail_screen.dart` | 3 |

This is the largest single piece of Scope B. `settings_screen.dart` carries the
most density — the Legal section and the change-password dialog.

`test/l10n/arb_parity_test.dart` already fails on a missing key, so parity is
enforced for free.

## UI

`settings_screen.dart` is 536 lines of ad-hoc rows built by three private helpers
(`_buildListTile`, `_buildSectionHeader`, `_buildSwitchTile`) called twenty times.
Those become two public widgets in
`lib/screens/settings/widgets/settings_section.dart`:

- `SettingsSection({required String title, required List<Widget> children})`
- `SettingsRow({required String title, String? subtitle, Widget? leading, Widget? trailing, VoidCallback? onTap})`

One place to get text scaling, tap targets and dividers right, instead of twenty.
Also shortens the screen materially, which is the "optimise the UI" ask made
concrete rather than aesthetic.

`lib/screens/settings/widgets/settings_snackbar.dart` mirrors
`chat_snackbar.dart`, following
`bananatalk_app/lib/pages/settings/widgets/settings_snackbar.dart`. One place
reports a transient outcome per surface.

## Theme

Only **5 colour literals** remain across these files — 2 in
`edit_profile_screen.dart`, 3 in `main_shell.dart`. The profile upgrade already
swept them.

The work is therefore not a sweep but a **gate**: extend the theme test to
`lib/screens/profile`, `lib/screens/settings` and `lib/screens/main_shell.dart`
with the wide regex, so the new section files and widgets cannot reintroduce
literals. Plus token-resolution assertions in both themes, since banning literals
proves nothing about what the replacement resolves to.

## Responsive

Profile and Settings are lists, so they constrain to `kSheetMaxWidth` and centre
on expanded windows, using the breakpoint helper Scope A introduced.

Text scaling is the real risk, as in Scope A: no fixed-height container wrapping
text, `Flexible` in every text-bearing `Row`, and `SettingsRow` gets this once
rather than each of the twenty call sites getting it separately.

## Error handling

| Failure | Behaviour |
|---|---|
| A section save fails | That section stays dirty and shows its error; the other sections are untouched. This is the independent-save property the profile upgrade built. |
| Photo reorder fails | The previous order is restored locally — an optimistic reorder that silently reverts on the next fetch would look like the app forgetting. |
| Like / super-like fails | Snackbar; the deck is not modified, so the profile remains swipeable. |
| Show-distance or online-status toggle fails | Revert the switch and report. A switch that stays flipped after a failed write is a lie about server state. |
| Profile load fails | Error state distinct from empty, as everywhere else. |

## Testing

**Navigation.** Three tabs when chat is enabled, two when not. A stale
`bottomNavIndexProvider` value beyond the built list clamps instead of throwing —
that is the specific hazard of removing an `IndexedStack` child. Settings is
reachable from Profile's gear and is not a tab.

**Ownership.** Edit Profile no longer contains a preferences editor or an
online-status switch. My Profile's preferences block is read-only and taps through
to `/discover/filters`.

**Sections.** Each saves independently: a failure in one leaves the others
unsaved-but-intact. The age validator is one function with one set of tests
rather than three copies.

**Like / super-like.** A successful like removes the profile from the deck; a
failed one leaves it. This is the pair that stops a liked profile reappearing.

**Photo reorder, backend.** A permutation succeeds and sets `isPrimary` on the
first. A list containing an id the caller does not own is 422. A list that is a
subset — a dropped photo — is 422, not a silent deletion.

**Preview.** `ProfileDetailScreen` with `isPreview: true` shows no like,
super-like or report action; with the flag absent, every existing action is still
present.

**Toggles.** A failed write reverts the switch.

**Localization.** ARB parity across 13 locales, enforced by the existing test.

**Theme gate** extended to profile, settings and the shell, plus token-resolution
assertions in both themes.

**Layout.** Profile and Settings pump clean at compact and expanded widths and at
text scale 1.0 and 2.0 — `tester.takeException()` null in all four combinations.

**Gate:** `flutter analyze` at 0 errors and 0 warnings, full `flutter test`, and
the backend suite green. Both repositories.
