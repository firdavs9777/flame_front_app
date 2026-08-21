# Scope A — Discover and its Filters Become Real

First of three scopes agreed for the pre-release push:

- **A (this spec)** — Discover, its filters, and the distance it displays.
- **B** — Profile pages, Settings, and the tab bar, which cannot be settled
  separately because the honest fix for the tab bar is deciding whether Settings
  deserves a top-level destination at all.
- **C** — Notifications. Blocked on Firebase credentials (ops, not code) plus
  `firebase_messaging`, which is not yet a dependency.

Spans two repositories: the app (`flame`) and the backend
(`language_exchange_backend_application/flame`).

## Why

Three things on this surface are not true today.

**The distance slider does nothing.** `discoveryService.discover()` carries the
comment *"No distance filtering yet — most users lack `locationGeo`."* The user
drags a kilometre slider, taps Apply, and gets a success toast for a preference
the query ignores.

**Every card claims "0 km away."** `toDiscoverUser` hardcodes `distance: 0` and
`User.distanceText` renders `'${distance.toStringAsFixed(0)} km away'`, shown on
every swipe card (`profile_card.dart:199`) and on the detail screen (`:165`).

**The deck skips profiles.** `discover()` pages with `skip(offset)` over a filter
that excludes everyone already swiped. The excluded set grows as the user swipes,
so the result set shrinks beneath the offset and page two steps over profiles
never seen. This is the same defect class as the message-thread drift, from the
opposite direction.

Two further problems are structural rather than behavioural. The tab labelled
Discover renders `HomeScreen`, while the file named `discover_screen.dart` is
actually the filter sheet — so "Discover" means different things in different
files. And gender filtering works, but only from `me.lookingFor`, set once during
registration and unreachable afterwards.

## What is already in place

Worth stating, because it makes this scope far smaller than the follow-ups doc
implied:

- `User.locationGeo` exists, **2dsphere-indexed** (`models/User.js:147`).
- `PATCH /me/location` is live, and `userService` writes the pair together.
- `authService.register` writes `locationGeo` at signup.
- Registration **requires** location: `getCurrentPosition()` failing halts the
  flow with an "Open Settings" dialog. Every account created through the current
  app therefore has a point. Nulls belong to accounts predating that flow.
- The app has a complete `LocationService` (Geolocator, permission check and
  request, `getCurrentPosition`) and `CurrentUserNotifier.updateLocation`.

Nothing calls `updateLocation`, and `discover()` never issues a geo query. Those
are the two missing connections.

## Decisions taken

| Question | Decision |
|---|---|
| Accounts with no location, once distance filtering is on | **Always included.** Nobody silently disappears. |
| Geo operator | **`$geoWithin` + `$centerSphere`**, not `$near`. |
| Deck ordering | **`lastActive` descending**, unchanged. |
| Deck refill | **No offset at all** — fetch the head. |
| Filters shipping | Distance, gender preference, interests. |
| Online-only filter | **Dropped.** |
| Interests matching | Any overlap, hard filter. |
| The "0 km away" label | **Real distance, honouring `showDistance`.** |

### Why `$geoWithin` rather than `$near`

`$near` cannot appear inside `$or`, so it cannot express "within the radius **or**
location unknown". It also forces distance ordering, silently overriding
`sort({ lastActive: -1 })`. `$geoWithin` filters without sorting and composes
inside `$or`, so it satisfies both decisions above.

### Why no offset

The server already excludes everyone swiped, so "the next N unseen profiles" *is*
the first N of the filtered set. There is nothing to page past.

The alternative does not work here. The deck sorts by `lastActive`, which mutates
every time a user opens the app. A keyset cursor over a mutable sort key is
unstable by construction: a profile whose `lastActive` bumps between fetches is
re-served or skipped no matter how correct the cursor arithmetic is. Offset paging
over a shrinking set is broken; cursor paging over a moving sort key is also
broken; not paging is neither.

Rejected alternatives, for the record: a `(lastActive, _id)` keyset cursor —
matches the convention used for messages, but inherits the mutable-key problem,
so it buys consistency of style rather than correctness. A cursor on `_id` alone —
genuinely stable, but orders the deck by account age, sinking active users.

## Not in this scope

- Profile pages, Settings, the tab bar — Scope B.
- Notifications — Scope C.
- The Stories tray in Messages, which still shows fabricated stories attributed
  to real matches. A release blocker, but it lives in a different tab.
- Displaying distance anywhere outside the deck and the detail screen.
- A general rate limiter for the rest of `/flamebackend/v1`.

---

## Backend

### The query

`discoveryService.discover(viewerId, { limit, offset })` keeps its existing base
filter (self, excluded, not deleted), gender from `me.lookingFor`, and the age
window with its `preferencesSet` semantics. Two filters are added.

**Distance.** Applied only when `preferences.preferencesSet === true` **and** the
viewer has a `locationGeo` — you cannot measure from nowhere, and a viewer without
a location must get an unfiltered deck rather than an empty one.

```js
const KM_PER_RADIAN = 6378.1;

if (applyDistance) {
  filter.$or = [
    { locationGeo: { $geoWithin: { $centerSphere: [me.locationGeo.coordinates, km / KM_PER_RADIAN] } } },
    // Legacy accounts predating mandatory location capture. Including them costs
    // a little precision; excluding them would make a chunk of the existing user
    // base invisible to everyone, with nothing on screen saying so.
    { locationGeo: null },
    { locationGeo: { $exists: false } },
  ];
}
```

If a second `$or` is ever needed on this filter, both move under `$and` — a bare
second `$or` assignment would silently overwrite this one.

**Interests.** `preferences.interestsFilter: { type: [String], default: [] }` is
new. When non-empty:

```js
filter.interests = { $in: prefs.interestsFilter };
```

Any overlap, deliberately: requiring all of them empties the deck on a small user
base, and this app has a small user base.

**Gender is unchanged.** It already filters on `me.lookingFor`. This scope's
contribution is giving the app a way to edit that field.

### The `preferencesSet` consequence, stated rather than buried

Distance reuses the intent flag age uses, so a user who only ever touched the age
slider also acquires the default 50 km distance filter. The alternative — an
intent flag per preference — is more correct and more machinery. The shared flag
is acceptable because the filter sheet displays the distance value actually in
effect, so nothing is hidden. Revisit if users report a suddenly narrow deck.

### The refill contract

Dual-path, following the precedent set by the message cursor:

- **`offset` absent** (the new client): return the head, skip `countDocuments`
  entirely, and report `has_more: users.length === limit`. No `total`, no
  `offset` echoed — a response should not carry a field it did not compute.
- **`offset` present** (installed clients): behave exactly as today, `total`
  included. Honouring it preserves the skipping bug for those clients, which is
  the lesser evil: ignoring it would make their decks show duplicates instead,
  which is a visible malfunction rather than an invisible one.

### Distance in the payload

`toDiscoverUser(u)` gains an optional second parameter for the viewer, so its
other caller (`matchController`) keeps working and simply gets no distance.

`distance` is **omitted** — not zero — when:

- either side has no `locationGeo`, or
- the **target** has `preferences.showDistance === false`.

Computed with haversine from the two coordinate pairs. Not `$geoNear`: that would
force distance ordering, and the aggregation is unnecessary for a number this
cheap to derive.

This is the change the profile follow-ups doc predicted: *"The next change that
computes a distance must land `showDistance` enforcement with it."* It does.

**The flag is asymmetric, deliberately.** Only the *target's* `showDistance` is
consulted. Turning your own off hides your distance from others; it does not hide
theirs from you. This matches the existing treatment of `showOnlineStatus`, which
the follow-ups doc records as an intentional asymmetry. Stated here so it is not
read later as an oversight.

### Validation

`PATCH /me/preferences` accepts `interests_filter`, validated against the shared
interest token set and capped at 10 entries to match the registration cap and keep
the `$in` small. `max_distance` is validated to 1–500 km; the schema has no bounds
today.

---

## App

### Location refresh

On Discover open: if permission is already granted, fetch the position and PATCH
it **once per app session**, fire-and-forget. Never blocks or delays the deck —
location is enrichment.

If permission was revoked after registration, ask once. If refused, the distance
slider renders **disabled with a one-line reason**. A control that cannot work
must not look like one that can; that is the exact defect this scope removes, so
it must not reappear in a new costume.

### Naming

| Now | Becomes |
|---|---|
| `screens/home/home_screen.dart` → `HomeScreen` | `screens/discover/discover_screen.dart` → `DiscoverScreen` |
| `screens/discover/discover_screen.dart` → `DiscoverScreen` (the filter sheet) | `screens/discover/discover_filters_screen.dart` → `DiscoverFiltersScreen` |
| route `/discover` | route `/discover/filters` |

The tab says Discover, so the deck should be the thing called Discover.

### Filter sheet

Age range (already works), distance (now real), gender preference writing
`lookingFor`, interests multi-select writing `preferences.interestsFilter`.

`EnvConfig.advancedFiltersEnabled` is deleted: of the three filters it gated, two
become real and one was dropped.

Gender writes `lookingFor` rather than introducing `preferences.genderPreference`.
Two fields meaning the same thing will disagree, and the query already reads
`lookingFor`.

### Applying changed filters

Saving the sheet clears the deck and fetches the head. It cannot merge: the
profiles already held were selected under the old predicate, so keeping them
would show results the new filters exclude — which reads as the filter not
working. Clear, then fetch.

### Deck refill

`DiscoveryNotifier` loses `_offset`. `loadMore()` becomes `refill()`:

- an in-flight guard, which the notifier lacks today — a double-fire currently
  advances the offset twice and appends without deduping;
- fetch the head;
- dedupe by id against the cards already held, since the head necessarily
  re-includes anything fetched but not yet swiped;
- triggered when fewer than three cards remain.

Three is a buffer, not a guarantee: a user swiping faster than the round trip can
still empty the deck momentarily. That renders as the loading state rather than
the empty state, which is why those two must stay distinct — an in-flight refill
must never look like "you've seen everyone".

`DiscoveryResult` drops `total` and `offset`. Both exist only to serve offset
paging, and the head path does not compute them; leaving them on the model as
`?? users.length` fallbacks would let a caller read a plausible-looking number
that means nothing.

### Empty and error states

Today one string guesses at both: *"Check back later or adjust your filters."*
Split into three distinct states:

| State | Copy | Action |
|---|---|---|
| Filters match nobody | "No one matches these filters" | **Relax filters** → opens the sheet |
| Genuinely seen everyone | "You've seen everyone nearby" | Refresh |
| Fetch failed | The error | Retry |

The third must never render as either of the first two. That collapse is the
defect just removed from the chat thread, and it is latent here.

---

## Error handling

Location is enrichment and never gates the deck:

| Failure | Behaviour |
|---|---|
| Permission denied or revoked | Deck loads normally; distance slider disabled with a reason. Asked at most once per session. |
| `getCurrentPosition` fails or times out | Silent. Retry next session. |
| `PATCH /me/location` fails | Silent, best-effort. The point stored at registration stands. |
| Filter save fails | Sheet stays open, error shown, deck **not** refreshed. It must not look saved when it is not. |
| Discover fetch fails | Error state, distinct from either empty state. |
| Refill fails | Keep the cards already held. No wipe. Retry at the next threshold crossing. |

Edge cases: a viewer with no location gets no distance filter. An
`interestsFilter` matching nobody produces the "no one matches" state, not a
blank screen.

---

## UI, localization, theming, responsiveness

### Shared interest catalogue

Two hardcoded catalogues exist today: `allInterests` in the filter sheet (plain
strings) and `_InterestItem` in `step_bio_interests.dart` (with icons and
colours). They will drift, and an interests filter whose vocabulary differs from
what users actually selected matches nothing.

`lib/core/interests/interest_catalogue.dart` becomes the single source: a stable
English **token** (what is stored on `user.interests`, what the `$in` matches), an
ARB key for its label, and the icon and colour registration already uses. Both
surfaces read it; the backend validates against the same token set.

Stored values do not change, so there is no data migration. The token is the key;
the label is presentation.

**The token list has to exist in both repositories**, since the backend validates
`interests_filter` against it. `flame/config/interests.js` holds the server's copy,
and a test in each repo asserts its own list is what the other expects — two
hardcoded lists that silently diverge is worse than one hardcoded list.

**Existing `user.interests` values are not constrained by it.** The registration
schema accepts `z.array(z.string().min(1))`, so stored interests may contain
values outside any catalogue — free text from an older client, or a token since
renamed. Validation applies to the *filter* only, where we control the input. The
consequence is honest but worth naming: a user whose stored interests are all
off-catalogue can never be surfaced by an interests filter. Reconciling stored
values is a migration, and it belongs to whatever change decides the catalogue is
final.

### Localization

24 hardcoded strings across the three Scope A files, including `'Age Range'`,
`'Maximum Distance'`, `'Show Me'`, `'Apply Filters'`, `'No more profiles'`,
`'Failed to load profiles'`, and the interest labels.

`distanceText` is the one that is not merely a translation. It hardcodes English
*and* kilometres. The wire stays kilometres; display converts, choosing the unit
from the locale — miles for `en_US`, kilometres elsewhere — formatted with
`NumberFormat`. A US user reading "8 km away" is a bug in a different disguise.

All 13 locales; `test/l10n/arb_parity_test.dart` already fails on a missing key.

### Light and dark

38 colour literals in the Scope A surfaces: `profile_card.dart` 18,
`home_screen.dart` 12, `discover_screen.dart` 8. Replaced with semantic tokens
from `lib/theme/app_tokens.dart`, and the theme gate extends to
`lib/screens/home`, `lib/screens/discover`, and `lib/widgets/profile_card.dart`.

`profile_card` is the interesting case: it draws text **over a user photo**, so
it needs `onOverlay` *and* a gradient scrim. A bright photo destroys white text
regardless of which theme is active — a scrim is a legibility requirement, not a
decoration.

The swipe overlay colours (like / nope / super-like) are fixed accents in both
themes, like `readReceipt`: named constants in `AppColors`, not tokens pretending
to vary.

Token-resolution assertions accompany the sweep, as with chat: banning literals
proves nothing about what the replacement resolves to.

### Responsive

Only three files in the app use any responsive primitive, and there is no
breakpoint helper.

`lib/core/layout/breakpoints.dart` introduces one: compact below 600 logical
pixels, expanded at or above, matching Material's window size classes. Two
breakpoints, because a third would be invented rather than needed.

- **Swipe deck**: constrained to roughly 420 logical pixels wide and centred. A
  full-bleed card on a tablet is absurd. Height capped too, so landscape does not
  produce a letterboxed smear.
- **Filter sheet**: full-screen on compact, width-constrained on expanded.
- **Safe areas**: bottom nav plus gesture inset respected on both.

**Text scaling is the larger risk.** A fixed-height box plus large accessibility
text overflows — the same failure the chat popup menu produced. Rules for this
scope: no fixed-height container wrapping text; every text-bearing `Row` uses
`Flexible` or `Expanded`; the interest chips wrap rather than scroll horizontally.

---

## Testing

### Backend

- A profile inside the radius is returned; one outside is not.
- A profile with **no location is returned regardless** — the chosen behaviour,
  pinned rather than assumed.
- A viewer with no `locationGeo` gets everyone: no distance filter.
- Distance applies only when `preferencesSet` is true.
- Interests match on any overlap; an empty `interestsFilter` filters nothing.
- **Ordering stays `lastActive` with the geo filter applied.** This is what stops
  someone later swapping `$geoWithin` for `$near` and quietly losing recency.
- Head path omits `total` and derives `has_more` from a full page; the legacy
  `offset` path is unchanged.
- **The drift test**: swipe N profiles, refetch the head, assert every returned
  profile is unseen and none were skipped.
- Distance payload: real for two located users; omitted when the target set
  `showDistance: false`; omitted when either side lacks a location — that last
  case is the one that used to print `0 km away`.
- `max_distance` outside 1–500 and `interests_filter` with an unknown token are
  both 422, not silently accepted.

### App

- `refill()` dedupes by id; concurrent calls fire once; a failed refill keeps the
  deck intact.
- Error state is distinct from both empty states.
- The distance slider is disabled, with its reason visible, when permission is
  absent.
- A failed filter save leaves the sheet open and does not refresh the deck.
- Location PATCHes at most once per session.
- Distance renders in miles under `en_US` and kilometres under `ko`, from the same
  wire value.
- **Layout**: the deck and the sheet pump clean at compact and expanded widths and
  at text scale 1.0 and 2.0 — `tester.takeException()` null in all four
  combinations.
- Theme gate extended, plus token-resolution assertions in both themes.

### Gate

`flutter analyze` at 0 errors and 0 warnings, full `flutter test`, and the backend
suite green. Both repositories.
