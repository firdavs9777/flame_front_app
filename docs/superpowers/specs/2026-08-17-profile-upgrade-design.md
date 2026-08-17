# Profile Upgrade — Design

**Date:** 2026-08-17
**Sub-project:** C of the chat/profile decomposition
**Repos:** `~/Projects/BananaTalk/backend` (the `flame/` sub-app) and `~/Desktop/Flame/flame_front_app`
**Reference:** `~/Projects/BananaTalk/bananatalk_app` — consulted, mostly *not* followed; see below
**Predecessors:** the B1–B3 chat enrichment spec, and `2026-08-17-chat-search-archive-translation-design.md`

## Problem

Flame's profile looks thin next to BananaTalk's — 2,024 lines against 19,800 — and
that comparison is misleading in both directions.

It is thin for a reason that is mostly correct: BananaTalk's profile is
`followers`, `followings`, `moments`, `visitors`, `highlights`, `topics_edit`,
`occupation_edit`, `school_edit`, `blood_type_edit`, `mbti_edit`. Followers and
followings are a **social graph**, and Flame is built on mutual matching, where a
one-way follow does not exist. Moments is a feed product. Blood type and MBTI are
language-exchange conventions. Copying that list is how Flame ended up with a
675-line sticker picker calling five endpoints that have never existed.

But the audit found something the size comparison hides: **three things the
profile already tries to do never reach a server.**

| App calls | Backend has |
|---|---|
| `PATCH /users/me/preferences` | nothing |
| `PATCH /users/me/location` | nothing |
| `PATCH /users/me/notifications` | nothing — settings live at `PUT /notifications/settings` |
| `PATCH /users/me/photos/reorder` | nothing |

`flame/routes/users.js:22` says so directly:

> `// Other fields (preferences/settings/location) intentionally not exposed in`
> `// PATCH /users/me yet — they get dedicated routes in Plan 2.`

Plan 2 never happened. So Discovery Preferences renders age range, distance and
gender, and saving them goes nowhere.

Separately, **dark mode is configured and then ignored.** `MaterialApp` has
`darkTheme` and `themeMode`, `AppTheme` has real `ColorScheme.light` and
`ColorScheme.dark` under Material 3 — and **349 hardcoded colours** across the app
override all of it.

## Scope

**In:** the missing preference and location routes, privacy enforcement, an edit-profile
rework, and a theme sweep of profile and settings.

**Out, and deliberately:**

- **Photo reorder.** `photos` is ordered and `primaryPhoto` reads `photos.first`,
  so reordering is meaningful. But the chain is dead two levels deep:
  `user_service.reorderPhotos` is called only by `user_provider.dart:151`, and
  **nothing calls that provider method** — no screen, no widget. Adding a route to
  serve an unreachable provider method is the sticker mistake again. Cut until a
  UI wants it.
- **The other ~300 hardcoded colours**, 104 of them in chat. Fixing profile and
  settings makes dark mode correct on the screens being reworked anyway; going
  app-wide is a large mechanical diff with no feature in it and belongs in its own
  change. **Consequence, stated plainly: dark mode will look inconsistent between
  the profile tab and the chat tab until that follow-up happens.**
- **Anything from BananaTalk's profile feature list.** See above.

## What already exists — do not rebuild

Verified in the code:

| Capability | Where | State |
|---|---|---|
| `minAge`, `maxAge`, `maxDistance` | `flame/models/User.js:31-33` | stored, no route to set |
| `showDistance`, `showOnlineStatus` | `flame/models/User.js:34-35` | stored, no route, **not enforced** |
| `location`, `locationGeo` + 2dsphere index | `flame/models/User.js:78-79,138` | stored, no route to set |
| `notificationSettings` | `flame/models/User.js:100` | stored, served by `PUT /notifications/settings` |
| Light and dark `ColorScheme` | `lib/theme/app_theme.dart:355,482` | correct, and overridden 349 times |
| `themeMode` persistence | `settingsProvider`, tested | works |
| Dead controls in profile/settings | — | **none**, unlike chat |

Every field this project needs is already on the model. Nothing new is stored.

---

## Wiring

### Contracts — fixed by the shipped app

```
PATCH /flamebackend/v1/users/me/preferences
body: { min_age?, max_age?, max_distance?, show_distance?, show_online_status? }
resp: { success: true, data: { preferences: {...} } }

PATCH /flamebackend/v1/users/me/location
body: { latitude, longitude }
resp: { success: true, data: { location: {...} } }
```

Snake_case, every preference field optional. `user_service.dart` reads
`data['preferences']` and `data['location']` respectively, falling back to
`data` — so either shape works, but emit the named key.

Both routes mount **before** `/:id` in `flame/routes/users.js`, for the reason
the file already documents for `/me/photos`: otherwise `me` is read as an id.

### The non-obvious part

`PATCH /me/location` must write **both** `location` and `locationGeo`. Discover
queries the 2dsphere index on `locationGeo` (`User.js:138`); writing only
`location` would store the coordinates and leave Discover ranking on the old
ones, which reads as "distance filtering is broken" rather than "location did not
save".

### Notifications: fix the app, not the backend

`PUT /notifications/settings` already works and has passing tests. The app has
**two** callers for one feature: `notification_settings_screen.dart` uses the
working path, and `user_service.updateNotificationSettings` posts to
`/users/me/notifications`, which 404s.

So the fix is **deleting the broken method**, not adding a route to match it.
Adding one would leave two paths to one feature, free to drift — the shape that
produced the pin response bug, the mute contract bug and the refresh bug in this
same codebase.

---

## Privacy

`showDistance` and `showOnlineStatus` become saveable through the preferences
route above. That is the easy half.

**The half that matters: nothing enforces them today.**

For `showOnlineStatus` that is a live leak. `toDiscoverUser` returns
`is_online: u.isOnline` unconditionally (`discoveryService.js:20`), and the
presence fan-out broadcasts regardless. A toggle that saves and changes nothing is
worse than no toggle, because it makes a promise.

For `showDistance` the situation is different and worth stating rather than
papering over: **`toDiscoverUser` hardcodes `distance: 0`**
(`discoveryService.js:19`), and the file says why — *"No distance filtering yet —
most users lack `locationGeo`."* So there is no distance to hide. Enforcement
there is a guard on a value that does not exist yet.

That gives a clear split:

- **`showOnlineStatus` is enforced now.** `emitPresence` and the `presence:bulk`
  snapshot must skip a user who has it off, and `toDiscoverUser` and
  `toConversation` must report them offline. This closes a real leak.
- **`showDistance` is stored and saveable, and the toggle is NOT shown in the UI
  yet.** Rendering a control that governs a number always reported as `0` would be
  the dead-button pattern in a new costume. It becomes real in the same change
  that makes distance real — which needs `locationGeo` populated for actual users,
  and that follows from `PATCH /me/location` finally existing.

Enforcement goes where the data leaves the server, not at one chokepoint:

This is the shape Phase A's block enforcement took: applied at every surface
rather than one, because the surface nobody remembered is the one that leaks.
`visibilityService` is the precedent — one place answers the question and every
caller asks it.

**Deliberate asymmetry:** hiding your online status does not hide *theirs* from
you. Making it reciprocal is a product decision with a real argument either way,
and it is not being made here.

---

## UI and theming

### Edit profile

One long form becomes sectioned cards — Photos, About, Interests, Preferences —
each saving independently, with inline validation rather than a snackbar after
the fact. The current screen validates on submit, so a bad age is discovered
after the user has stopped thinking about it.

Preferences move onto this screen as *editable* controls, since they finally have
a route.

### Profile

A proper header, and the state the model already carries and nothing shows:
`isVerified`, `isPremium`, `premiumExpiresAt`. `/billing/status` exists and is
already called; no screen displays the result.

### The theme sweep

~45 hardcoded colours across `lib/screens/profile` and `lib/screens/settings`,
replaced with semantic tokens:

| Hardcoded | Token |
|---|---|
| `Colors.white` (surfaces) | `colorScheme.surface` |
| `Colors.black87` (body text) | `colorScheme.onSurface` |
| `Colors.grey[600]` (secondary text) | `colorScheme.onSurfaceVariant` |
| `Colors.grey[200]` (fills) | `colorScheme.surfaceContainerHighest` |
| `Colors.grey[300]` (dividers) | `dividerColor` |

Brand colours stay literal: `AppTheme.primaryColor` is the brand in both themes
and is not a theme-varying token.

## Testing

- **Routes** — each preference field persists; a partial body updates only what
  it names; a non-owner cannot write another user's preferences; `latitude` and
  `longitude` are both required; `locationGeo` is written alongside `location`,
  asserted by a 2dsphere query returning the *new* position.
- **Privacy enforcement** — the tests that carry the design. A user with
  `showOnlineStatus: false` reads as offline in Discover, in the conversation
  list, and in the presence snapshot. Each surface asserted separately, because
  one shared helper passing does not prove three call sites use it. `showDistance`
  gets a persistence test only — there is no distance to hide until
  `discoveryService` stops hardcoding `distance: 0`.
- **App** — `updateNotificationSettings` is gone and nothing references it;
  edit-profile validation rejects an under-18 age before any request; each
  reworked screen pumps in light and dark without exception.
- **Theme** — a test asserting no `Colors.` literal remains in the swept
  directories. Lint-like rather than golden: goldens on themed screens break on
  every palette change and get regenerated without being read.

Backend tests follow `flame/__tests__` conventions and the four standing
corrections: fixture names ≥2 characters, S3 env vars before any `require`, every
required service cleared from the require-cache array including `matchService` and
`Match`, and **teardown registered before anything that can throw** — that last
one turned a correct RED run into a five-minute hang during the previous project.

## Rollout

Wiring first, then privacy enforcement, then UI and theming. Modernising a screen
whose Save button does not reach a server means doing the work twice, and the
theme sweep touches the same files — better to move a widget once.

Nothing here adds a collection or an index, so no legacy-index check is required
before deploying. `PATCH /me/location` is the only route touching an indexed
field, and the index already exists.
