# Profile Upgrade — Follow-ups

Parked during execution of `2026-08-17-profile-upgrade.md`. Each was found by a
review, ruled on deliberately, and left undone for a stated reason. Recorded here
because the execution ledger lives in git-ignored scratch and does not survive.

## Product decisions, not defects

- **`maxDistance` is saveable, user-editable, and read by nothing.** Nothing in
  `flame/` reads `preferences.maxDistance`, yet it is now writable and renders as
  a slider in Discover's filter and in Edit Profile → Preferences. This is the
  same defect the spec reasoned carefully about for `showDistance` — a control
  over a value the server never uses — and then shipped unremarked for
  `max_distance`. Either hide the slider until Discover filters on it, or record
  the gap in the spec the way `showDistance` is recorded.
- **`showDistance` enforcement.** Deliberately deferred: `toDiscoverUser`
  hardcodes `distance: 0` and nothing in `flame/` computes a distance, so there
  is nothing to hide. **But the spec named `PATCH /me/location` existing as the
  precondition for distance becoming real, and that route now exists.** The next
  change that computes a distance must land `showDistance` enforcement with it,
  across every surface — the same all-surfaces treatment `showOnlineStatus` just
  received, since `toDiscoverUser` feeds both Discover and the conversation list.
- **Dead like / super-like buttons.** `lib/screens/profile/profile_detail_screen.dart:255-271`
  — `onTap` pops the sheet, the body is `// Handle super like` / `// Handle like`.
  Reachable from Discover and from chat. Belongs to the swipe surface rather than
  this plan.

## Wiring that is correct but not yet reachable

- **Premium state cannot display until the server sends it.** `User.isPremium`
  and `premiumExpiresAt` now parse from either casing, and `User.isPremiumActive`
  is the single rule both `swipe_provider` and the profile header use. But
  `authService.toPublic` sends neither field, and `/billing/status` returns a
  hardcoded `is_premium: false`. So the badge stays hidden and swipe-undo stays
  gated off for everyone. Two things are needed: those fields in `toPublic`, and
  a real billing status.
- **A single entitlement source.** Premium is written onto `authProvider`'s user
  by `auth_provider.dart:128-137` from the billing call, while
  `currentUserProvider` — which the profile header and `swipe_provider._canUndo`
  both read — never receives it. Re-pointing one consumer would create a second
  disagreeing source for a money-relevant boolean, so nothing was re-pointed.
  Fixing it properly means one provider owning entitlement. Note that
  `AuthNotifier` constructs its services as field initializers and calls
  `_init()` from its own constructor, so it currently has no injection seam and
  the alternative wiring cannot be tested.
- **Photo reorder.** `CurrentUserNotifier.setMainPhotoAt` and
  `UserService.reorderPhotos` are kept deliberately, but
  `PATCH /users/me/photos/reorder` **does not exist** — the string `reorder`
  appears nowhere in the backend repository. The "Set as main photo" menu item
  was removed because every tap 404'd. Adding the route is all a future change
  needs; until then these two methods have no caller outside
  `test/providers/photo_management_test.dart` and protect no live user path.
- **`CurrentUserNotifier.updateLocation` has no caller** in `lib/` or `test/`.
  `PATCH /me/location` was built to serve it. Worth stating plainly: that is
  verbatim the argument the spec used to *exclude* photo reorder — "adding a
  route to serve an unreachable provider method is the sticker mistake again" —
  and the plan applied its own test asymmetrically. Either give the app a caller
  (a location permission prompt on Discover is the obvious one, and it is what
  would finally populate `locationGeo` for real users) or the route waits.

## Correctness, small

- **`settings_screen.dart:22-24,91-94` collapses loading and error.** It reads
  `userState.valueOrNull` with `?? true`, and `loadUser()` sets
  `AsyncValue.error` without preserving previous data. So a transient reload
  failure renders "Show Online Status" as on — disabled — even when the stored
  value is off. It writes nothing while wrong and self-corrects on the next
  successful load. Its sibling `EditProfileScreen` uses a full `when(...)` and is
  not affected. Needs a test for the error branch, which nothing covers today.
- **`preferencesSet` is exposed in `GET /users/me`'s `preferences` object.** It
  is the caller's own document and the wire tolerates unknown keys, and it is not
  writable by any route — but it is an internal sentinel appearing in a public
  response shape.
- **`updatePreferences` now does an extra `findById` per PATCH**, needed to
  validate the merged age range against stored state. A single-round-trip
  aggregation-pipeline form exists; it trades obvious correctness for a much
  harder read on a low-frequency user-initiated write. Revisit only if this path
  becomes hot.

## Consistency and hygiene

- **The theme lint gate is narrower than its name.** `test/theme/profile_settings_theme_test.dart`
  bans `Colors.white|black|grey|black87|white70|white60|white54`, so
  `Colors.blue`, `Colors.amber` and direct `AppColors.*` all pass it. Four hits
  remain in the swept directories beyond the deliberately-spared
  `Colors.transparent` / `Colors.red`, all measured legible in dark. Widening the
  regex would make the gate mean what its name says.
  - **More importantly, the gate cannot see a token that resolves to the wrong
    colour.** `context.fill` silently equalled `context.surface` and
    `context.secondaryText` silently equalled `context.onSurface` in both themes
    — because `AppTheme` passed neither `surfaceContainerHighest` nor
    `onSurfaceVariant` and Flutter's getters fall back — which made the reworked
    edit-profile form's six text fields invisible while the lint reported clean.
    `test/theme/app_tokens_test.dart` now pins those two inequalities. **Any new
    token needs the same treatment**: banning literals proves nothing about what
    the replacement resolves to.
- **Light-mode caption contrast is ≈3.48:1, below WCAG AA's 4.5:1.**
  `secondaryText` is `AppColors.gray600`, which matches `AppTypography.caption`'s
  own hardcoded `gray600` shipping in `app_card.dart` and `app_badge.dart` — so
  this is app-wide and pre-existing, not introduced here, and diverging locally
  would make the token disagree with every unswept screen. `gray700` would give
  ≈5.31:1. Fix app-wide or not at all.
- **In dark mode `fill` and `divider` are both `gray800`**, so a divider drawn on
  a fill is invisible there. The card boundary against `surfaceDark` still
  delineates shapes.
- **~70 duplicated lines** — the image-picker bottom sheet plus `_uploadPhoto`
  exists near-identically in `edit_profile_screen.dart` and
  `my_profile_screen.dart`. The age validator and its message appear three times
  verbatim in `edit_profile_screen.dart`. `Colors.red` is used there where the
  same branch uses `AppTheme.errorColor` elsewhere.
- **If `edit_profile_screen.dart` grows a sixth section, split it**: one file per
  section under `lib/screens/profile/edit_profile/`, leaving the screen as the
  typedefs plus a composition root. 897 lines was ruled earned for five
  independently-saving sections; a sixth changes that.
- **`swipe_provider._canUndo` has no test coverage at all.** The rule it delegates
  to is directly tested (`test/models/user_premium_test.dart`), which is where the
  risk lived, but the gate itself is untested.

## Out of scope by design, restated so it is not mistaken for an oversight

- **The other ~300 hardcoded colours, 104 of them in chat.** Dark mode will look
  inconsistent between the profile tab and the chat tab until that sweep happens.
  The spec says so explicitly.
- **Typing and read-receipt relays imply presence** and are not guarded by
  `showOnlineStatus`. They fire only during active use in an already-open
  conversation and are block-checked. This is a decision, not a miss; the spec's
  Privacy section should say so, since the code reads as an omission.
- **Hiding your own online status does not hide others' from you.** The asymmetry
  is deliberate and pinned by a test.
- **The presence guards fail OPEN to visible.** A missing `preferences`
  sub-document is the default state and its default is `showOnlineStatus: true`,
  so failing closed would hide presence for every legacy document.

## Unrelated, still outstanding, higher priority than anything above

- **Two credentials pasted into a chat transcript remain unrotated** — a MongoDB
  connection string including its password, and a Google OAuth client secret.
- **`/flamebackend/v1/auth/*` has no rate limiter**, so login is open to brute
  force.
