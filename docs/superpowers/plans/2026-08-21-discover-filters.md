# Scope A — Discover and Filters Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Discover's filters real — distance, gender and interests actually filter — stop the deck skipping profiles, and replace the fabricated "0 km away" with a real distance that honours `showDistance`.

**Architecture:** The backend gains a `$geoWithin` distance filter and an interests filter, computes real distance with haversine, and serves the deck's head instead of an offset page. The app connects the location plumbing that already exists, rebuilds the filter sheet against filters that now work, and replaces its offset paging with dedupe-on-refill.

**Tech Stack:** Flutter 3.38.x, Riverpod, `geolocator`, `intl`. Backend: Node, Express, Mongoose (2dsphere), `node:test` + `supertest`.

**Spec:** `docs/superpowers/specs/2026-08-21-discover-filters-design.md`

## Global Constraints

- **Two repositories.** App: `/Users/davis/Desktop/Personal/flame`, branch `feat/discover-filters`. Backend: `/Users/davis/Desktop/Personal/language_exchange_backend_application`, branch `main` (flame is the `flame/` subdirectory). Commit separately, never mix.
- **App gate:** `flutter analyze` at **0 errors, 0 warnings** and `flutter test` fully green, before every commit.
- **Backend gate:** `node --test flame/__tests__/<file>.test.js` from the backend repo root, green.
- **No deploy gate.** Omitting `offset` is safe against the current server (`parseInt(undefined) || 0` → 0 → the head). Until the backend deploys, the new filters simply do nothing, which is today's behaviour. The app must therefore treat `distance` of **null OR 0** as unknown, so the "0 km away" lie is gone even against an undeployed server.
- **No new hardcoded colours.** Every colour uses a token from `lib/theme/app_tokens.dart`, or a named `AppColors` constant when it genuinely does not vary by theme. `Colors.transparent` and `Colors.red` remain the only spared literals.
- **Every new user-facing string** goes in `lib/l10n/app_en.arb` **and all 12 sibling ARBs**. `test/l10n/arb_parity_test.dart` fails on a missing key.
- **Distance on the wire is always kilometres.** Unit conversion is display-only.
- **App test fakes:** subclass the real class and override. Build models with `User.fromJson({...})`, not constructors. See `test/providers/conversations_realtime_test.dart`.
- **Backend test harness:** `node:test` + `node:assert/strict` + `supertest`. Start **one** in-memory Mongo per file and rebuild only the route layer per test — copy the harness from `flame/__tests__/authRateLimit.test.js`. Do **not** copy the per-test `setup()`/`teardown()` pattern from older files; it spins a new database per test and goes stale by the sixth.

---

## File Structure

**Backend — modify:**
- `flame/services/discoveryService.js` — haversine, real distance, distance + interests filters, head path
- `flame/routes/discovery.js` — offset becomes optional; response shape
- `flame/models/User.js` — `preferences.interestsFilter`
- `flame/routes/users.js` — `interests_filter` in the PATCH schema, `max_distance` floor
- `flame/controllers/userController.js` — snake→camel for `interests_filter`
- `flame/services/userService.js` — `PREFERENCE_FIELDS`

**Backend — create:**
- `flame/config/interests.js` — the canonical token list
- `flame/__tests__/discoverFilters.test.js`
- `flame/__tests__/discoverDistance.test.js`

**App — create:**
- `lib/core/interests/interest_catalogue.dart`
- `lib/core/layout/breakpoints.dart`
- `lib/core/format/distance_display.dart` — km→locale unit
- `lib/screens/discover/discover_filters_screen.dart` (from the old `discover_screen.dart`)
- `lib/screens/discover/widgets/deck_states.dart` — empty / seen-everyone / error

**App — modify:**
- `lib/models/user.dart` — `distance` nullable, `distanceText` nullable
- `lib/services/discovery_service.dart` — drop offset/total
- `lib/providers/discovery_provider.dart` — `refill()`
- `lib/providers/filter_provider.dart` — interests + gender persistence
- `lib/services/user_service.dart` — `interestsFilter`
- `lib/screens/home/home_screen.dart` → `lib/screens/discover/discover_screen.dart`
- `lib/widgets/profile_card.dart` — tokens, scrim, nullable distance
- `lib/screens/profile/profile_detail_screen.dart` — nullable distance
- `lib/screens/auth/registration/steps/step_bio_interests.dart` — read the catalogue
- `lib/config/env.dart` — delete `advancedFiltersEnabled`
- `lib/main.dart` — route rename
- `lib/screens/main_shell.dart` — import rename
- `test/theme/profile_settings_theme_test.dart` / new discover gate

---

## Task 1: Backend — real distance in the payload

**Repo:** backend

**Files:**
- Modify: `flame/services/discoveryService.js:5-40`
- Test: `flame/__tests__/discoverDistance.test.js` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `toDiscoverUser(u, viewer)` — `viewer` optional. Emits `distance` as a **number of kilometres** or **null**. `haversineKm(a, b)` where each argument is `[lng, lat]`.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/discoverDistance.test.js`. Copy the harness block from `flame/__tests__/authRateLimit.test.js` (the `MODULES` list, `startDb`, `stopDb`, `freshApp`, `before`/`after`), then:

```js
const { toDiscoverUser, haversineKm } = require('../services/discoveryService');

// London and Paris, ~344 km apart.
const LONDON = [-0.1276, 51.5072];
const PARIS = [2.3522, 48.8566];

const userDoc = (over = {}) => ({
  _id: { toString: () => 'u1' },
  name: 'A', age: 30, gender: 'female', lookingFor: 'male',
  bio: '', interests: [], photos: [],
  isOnline: false, isVerified: false, lastActive: new Date(),
  createdAt: new Date(),
  preferences: {},
  ...over,
});

test('haversineKm measures a known distance', () => {
  const km = haversineKm(LONDON, PARIS);
  assert.ok(km > 330 && km < 360, `expected ~344, got ${km}`);
  assert.equal(Math.round(haversineKm(LONDON, LONDON)), 0);
});

test('distance is a real number when both sides have a location', () => {
  const target = userDoc({ locationGeo: { type: 'Point', coordinates: PARIS } });
  const viewer = { locationGeo: { type: 'Point', coordinates: LONDON } };

  const out = toDiscoverUser(target, viewer);

  assert.ok(out.distance > 330 && out.distance < 360);
});

test('distance is null when the target hid it', () => {
  const target = userDoc({
    locationGeo: { type: 'Point', coordinates: PARIS },
    preferences: { showDistance: false },
  });
  const viewer = { locationGeo: { type: 'Point', coordinates: LONDON } };

  assert.equal(toDiscoverUser(target, viewer).distance, null);
});

test('distance is null when either side has no location', () => {
  const located = userDoc({ locationGeo: { type: 'Point', coordinates: PARIS } });
  const viewer = { locationGeo: { type: 'Point', coordinates: LONDON } };

  assert.equal(toDiscoverUser(userDoc(), viewer).distance, null);
  assert.equal(toDiscoverUser(located, {}).distance, null);
  // This is the case that used to render "0 km away" on every card.
  assert.equal(toDiscoverUser(located, undefined).distance, null);
});

test('showDistance is asymmetric — hiding yours does not hide theirs', () => {
  const target = userDoc({ locationGeo: { type: 'Point', coordinates: PARIS } });
  const viewer = {
    locationGeo: { type: 'Point', coordinates: LONDON },
    preferences: { showDistance: false },
  };

  assert.ok(toDiscoverUser(target, viewer).distance > 330,
    'the viewer hiding their own distance must not blind them to others');
});

test('the existing single-argument callers still work', () => {
  // chatService.toConversation calls toDiscoverUser(doc) with no viewer.
  const out = toDiscoverUser(userDoc());
  assert.equal(out.distance, null);
  assert.equal(out.name, 'A');
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
node --test flame/__tests__/discoverDistance.test.js
```
Expected: FAIL — `haversineKm` is not exported, and `distance` is hardcoded `0`.

- [ ] **Step 3: Implement haversine and the real distance**

In `flame/services/discoveryService.js`, above `toDiscoverUser`:

```js
const EARTH_RADIUS_KM = 6371;

/**
 * Great-circle distance between two [lng, lat] pairs, in kilometres.
 *
 * Plain arithmetic rather than a $geoNear aggregation: the number is this cheap
 * to derive, and $geoNear would force the result set into distance order,
 * overriding the deck's lastActive sort.
 */
function haversineKm(a, b) {
  const toRad = (d) => (d * Math.PI) / 180;
  const [lng1, lat1] = a;
  const [lng2, lat2] = b;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(h));
}

/**
 * Kilometres between viewer and target, or null when it cannot or must not be
 * shown.
 *
 * Null rather than 0: the app used to render `distance` unconditionally, so a
 * hardcoded 0 became "0 km away" on every card in the deck. Null is the only
 * value that lets the client omit the label.
 *
 * Only the TARGET's showDistance is consulted. Turning your own off hides your
 * distance from others; it does not hide theirs from you — the same asymmetry
 * showOnlineStatus already has.
 */
function distanceBetween(target, viewer) {
  if (target.preferences && target.preferences.showDistance === false) return null;
  const t = target.locationGeo && target.locationGeo.coordinates;
  const v = viewer && viewer.locationGeo && viewer.locationGeo.coordinates;
  if (!t || !v) return null;
  return haversineKm(v, t);
}
```

Change the signature and the field:

```js
function toDiscoverUser(u, viewer) {
```
```js
    distance: distanceBetween(u, viewer),
```

Export both helpers:

```js
module.exports = { discover, toDiscoverUser, haversineKm };
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
node --test flame/__tests__/discoverDistance.test.js
node --test flame/__tests__/conversations.test.js
node --test flame/__tests__/onlineStatusPrivacy.test.js
```
Expected: all PASS. The latter two prove the single-argument callers
(`chatService.toConversation`) are unaffected.

- [ ] **Step 5: Commit**

```bash
cd /Users/davis/Desktop/Personal/language_exchange_backend_application
git add flame/services/discoveryService.js flame/__tests__/discoverDistance.test.js
git commit -m "feat(discover): compute a real distance instead of hardcoding zero

toDiscoverUser returned distance: 0 for everyone, and the app's distanceText can
only render a number — so every card in the deck said '0 km away'.

Haversine from the two coordinate pairs rather than a \$geoNear aggregation: the
number is this cheap to derive, and \$geoNear would force distance ordering over
the deck's lastActive sort.

Null, not 0, when it cannot be shown — null is the only value that lets the
client omit the label. Only the target's showDistance is consulted, matching the
asymmetry showOnlineStatus already has: hiding yours does not blind you to
theirs.

The viewer argument is optional, so chatService.toConversation keeps working and
simply gets no distance."
```

---

## Task 2: Backend — the distance filter

**Repo:** backend

**Files:**
- Modify: `flame/services/discoveryService.js` (`discover`)
- Modify: `flame/routes/users.js:39` (`max_distance` floor)
- Test: `flame/__tests__/discoverFilters.test.js` (create)

**Interfaces:**
- Consumes: Task 1's `haversineKm`.
- Produces: `discover(viewerId, { limit, offset })` applies a `$geoWithin` radius when `preferences.preferencesSet === true` and the viewer has `locationGeo`.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/discoverFilters.test.js` with the `authRateLimit.test.js` harness, plus these helpers:

```js
const User = require('../models/User');

const P = '/flamebackend/v1';
const LONDON = [-0.1276, 51.5072];
const NEAR_LONDON = [-0.1400, 51.5100];   // ~1 km
const PARIS = [2.3522, 48.8566];          // ~344 km

async function makeUser(app, email, over = {}) {
  const res = await request(app).post(`${P}/auth/register`).send({
    email, password: 'Hunter2!!', name: email.split('@')[0].slice(0, 20).padEnd(2, 'x'),
    age: 30, gender: 'female', lookingFor: 'male', interests: ['Travel'],
  }).expect(201);
  const id = res.body.data.user.id;
  if (Object.keys(over).length) await User.updateOne({ _id: id }, { $set: over });
  return { id, token: res.body.data.tokens.accessToken };
}

const geo = (coords) => ({ locationGeo: { type: 'Point', coordinates: coords } });

const deck = async (app, token) => {
  const res = await request(app).get(`${P}/discover?limit=50`)
    .set({ Authorization: `Bearer ${token}` }).expect(200);
  return res.body.data.users.map((u) => u.name);
};

test('a profile inside the radius is returned and one outside is not', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'radius-me@x.com', {
    ...geo(LONDON),
    'preferences.maxDistance': 50,
    'preferences.preferencesSet': true,
  });
  await makeUser(app, 'near@x.com', { gender: 'male', ...geo(NEAR_LONDON) });
  await makeUser(app, 'far@x.com', { gender: 'male', ...geo(PARIS) });

  const names = await deck(app, me.token);

  assert.ok(names.includes('near'), 'a 1 km profile must be in a 50 km radius');
  assert.ok(!names.includes('far'), 'a 344 km profile must not be');
});

test('a profile with no location is returned regardless', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'nullloc-me@x.com', {
    ...geo(LONDON),
    'preferences.maxDistance': 10,
    'preferences.preferencesSet': true,
  });
  await makeUser(app, 'nowhere@x.com', { gender: 'male', locationGeo: null });

  // Excluding them would make every account predating mandatory location
  // capture invisible to everyone, with nothing on screen saying so.
  assert.ok((await deck(app, me.token)).includes('nowhere'));
});

test('a viewer with no location gets no distance filter', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'noloc-me@x.com', {
    locationGeo: null,
    'preferences.maxDistance': 1,
    'preferences.preferencesSet': true,
  });
  await makeUser(app, 'anywhere@x.com', { gender: 'male', ...geo(PARIS) });

  assert.ok((await deck(app, me.token)).includes('anywhere'),
    'you cannot measure from nowhere; an unfiltered deck beats an empty one');
});

test('distance does not apply until preferences were deliberately written', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'untouched-me@x.com', {
    ...geo(LONDON),
    'preferences.maxDistance': 1,
    'preferences.preferencesSet': false,
  });
  await makeUser(app, 'faraway@x.com', { gender: 'male', ...geo(PARIS) });

  assert.ok((await deck(app, me.token)).includes('faraway'));
});

test('the deck stays in lastActive order with the geo filter applied', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'order-me@x.com', {
    ...geo(LONDON),
    'preferences.maxDistance': 500,
    'preferences.preferencesSet': true,
  });
  // The nearer profile is the STALER one. Under $near it would come first;
  // under $geoWithin plus sort(lastActive) the fresher one must.
  await makeUser(app, 'stalenear@x.com', {
    gender: 'male', ...geo(NEAR_LONDON), lastActive: new Date('2020-01-01'),
  });
  await makeUser(app, 'freshfar@x.com', {
    gender: 'male', ...geo(PARIS), lastActive: new Date('2030-01-01'),
  });

  const names = await deck(app, me.token);
  assert.deepEqual(names, ['freshfar', 'stalenear'],
    'this is what stops $geoWithin quietly becoming $near later');
});

test('max_distance below 1 is rejected', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'floor@x.com', {});
  await request(app).patch(`${P}/users/me/preferences`)
    .set({ Authorization: `Bearer ${me.token}` })
    .send({ max_distance: 0 })
    .expect(422);
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
node --test flame/__tests__/discoverFilters.test.js
```
Expected: FAIL — `far` and `stalenear` ordering wrong, `max_distance: 0` accepted.

- [ ] **Step 3: Add the distance filter**

In `flame/services/discoveryService.js`, inside `discover()` after the age block:

```js
  // Distance. Applied only when the user deliberately wrote preferences AND we
  // know where they are — you cannot measure from nowhere, and a viewer without
  // a location must get an unfiltered deck rather than an empty one.
  //
  // $geoWithin rather than $near for two reasons: $near cannot appear inside an
  // $or, so it could not express "within the radius OR location unknown"; and
  // $near forces distance ordering, silently overriding sort({ lastActive: -1 }).
  const KM_PER_RADIAN = 6378.1;
  const viewerCoords = me && me.locationGeo && me.locationGeo.coordinates;
  const maxDistance = prefs.maxDistance;

  if (prefs.preferencesSet === true && viewerCoords && maxDistance > 0) {
    // NOTE: if this filter ever needs a second $or, both must move under $and —
    // a bare second assignment would silently overwrite this one.
    filter.$or = [
      { locationGeo: { $geoWithin: { $centerSphere: [viewerCoords, maxDistance / KM_PER_RADIAN] } } },
      // Accounts predating mandatory location capture. Including them costs a
      // little precision; excluding them would erase them from the app.
      { locationGeo: null },
      { locationGeo: { $exists: false } },
    ];
  }
```

Pass the viewer through to the mapper at the end of `discover()`:

```js
  return { users: users.map((u) => toDiscoverUser(u, me)), total };
```

- [ ] **Step 4: Raise the `max_distance` floor**

In `flame/routes/users.js:39`, change:

```js
    max_distance: z.number().min(1).max(500).optional(),
```

A radius of 0 matches only a user standing on the exact same point, so it is a
filter that can only ever return nobody.

- [ ] **Step 5: Run tests to verify they pass**

```bash
node --test flame/__tests__/discoverFilters.test.js
node --test flame/__tests__/discoveryExclusion.test.js
node --test flame/__tests__/onlineStatusPrivacy.test.js
```
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add flame/services/discoveryService.js flame/routes/users.js flame/__tests__/discoverFilters.test.js
git commit -m "feat(discover): honour maxDistance, which was a live control the query ignored

The slider saved a preference nothing read — the service even said so: 'No
distance filtering yet — most users lack locationGeo.' The 2dsphere index and the
location route have existed the whole time.

\$geoWithin rather than \$near: \$near cannot sit inside an \$or, so it could not
express 'within the radius OR location unknown', and it would force distance
ordering over the deck's lastActive sort. A test asserts a stale-but-near profile
still sorts below a fresh-but-far one, which is what stops the operator being
swapped later.

Accounts with no location stay visible. Excluding them would erase every account
predating mandatory location capture, with nothing on screen saying so.

A viewer with no location gets no distance filter at all — an unfiltered deck
beats an empty one. max_distance now floors at 1: a radius of 0 can only ever
match someone standing on the exact same point."
```

---

## Task 3: Backend — the interests filter

**Repo:** backend

**Files:**
- Create: `flame/config/interests.js`
- Modify: `flame/models/User.js:30-45`
- Modify: `flame/routes/users.js` (schema)
- Modify: `flame/controllers/userController.js:18-29`
- Modify: `flame/services/userService.js:97-99`
- Modify: `flame/services/discoveryService.js` (`discover`)
- Test: `flame/__tests__/discoverFilters.test.js` (append)

**Interfaces:**
- Consumes: Task 2's filter block.
- Produces: `INTEREST_TOKENS` (a frozen array of strings) exported from `flame/config/interests.js`. `preferences.interestsFilter: [String]`. `PATCH /users/me/preferences` accepts `interests_filter: string[]`.

- [ ] **Step 1: Write the failing test**

Append to `flame/__tests__/discoverFilters.test.js`:

```js
test('interests filter matches on any overlap', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'int-me@x.com', {
    'preferences.interestsFilter': ['Music', 'Hiking'],
    'preferences.preferencesSet': true,
  });
  await makeUser(app, 'onematch@x.com', { gender: 'male', interests: ['Music', 'Food'] });
  await makeUser(app, 'nomatch@x.com', { gender: 'male', interests: ['Gaming'] });

  const names = await deck(app, me.token);

  assert.ok(names.includes('onematch'), 'one shared interest is enough');
  assert.ok(!names.includes('nomatch'));
});

test('an empty interests filter filters nothing', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'noint-me@x.com', {
    'preferences.interestsFilter': [],
    'preferences.preferencesSet': true,
  });
  await makeUser(app, 'anyone@x.com', { gender: 'male', interests: ['Gaming'] });

  assert.ok((await deck(app, me.token)).includes('anyone'));
});

test('interests_filter is persisted through the PATCH', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'patch-int@x.com', {});

  const res = await request(app).patch(`${P}/users/me/preferences`)
    .set({ Authorization: `Bearer ${me.token}` })
    .send({ interests_filter: ['Music', 'Art'] })
    .expect(200);

  assert.deepEqual(res.body.data.preferences.interestsFilter, ['Music', 'Art']);
});

test('an off-catalogue interest token is rejected', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'badtoken@x.com', {});

  await request(app).patch(`${P}/users/me/preferences`)
    .set({ Authorization: `Bearer ${me.token}` })
    .send({ interests_filter: ['NotAnInterest'] })
    .expect(422);
});

test('more than ten interest tokens are rejected', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'toomany@x.com', {});
  const { INTEREST_TOKENS } = require('../config/interests');

  await request(app).patch(`${P}/users/me/preferences`)
    .set({ Authorization: `Bearer ${me.token}` })
    .send({ interests_filter: INTEREST_TOKENS.slice(0, 11) })
    .expect(422);
});
```

- [ ] **Step 2: Run test to verify it fails**

```bash
node --test flame/__tests__/discoverFilters.test.js
```
Expected: FAIL — `interests_filter` is stripped by the schema and the field does not exist.

- [ ] **Step 3: Create the canonical token list**

Create `flame/config/interests.js`:

```js
// The canonical interest vocabulary.
//
// These tokens are what `user.interests` stores and what the discovery filter's
// $in matches. They are deliberately English and deliberately stable: the app
// localises the LABEL for each token and never the token itself, so translating
// the UI cannot break a filter.
//
// The app holds the same list in lib/core/interests/interest_catalogue.dart.
// A test in each repo asserts its own list matches the other's — two hardcoded
// lists that silently diverge would be worse than one.
const INTEREST_TOKENS = Object.freeze([
  'Travel', 'Music', 'Movies', 'Sports', 'Fitness', 'Food', 'Art', 'Gaming',
  'Reading', 'Photography', 'Coffee', 'Hiking', 'Dancing', 'Cooking',
]);

const MAX_INTEREST_FILTER = 10;

module.exports = { INTEREST_TOKENS, MAX_INTEREST_FILTER };
```

**Before writing this list, run** `grep -n "'" lib/screens/discover/discover_screen.dart | sed -n '/allInterests/,/];/p'` in the app repo and use the exact values found there, so the token set matches what users already have stored.

- [ ] **Step 4: Add the preference field and wire the PATCH**

`flame/models/User.js`, inside `preferencesSchema` (after `showOnlineStatus`):

```js
  // Discovery filter, NOT the user's own interests. Empty means "no interest
  // filter", which is why it defaults to [] rather than to the full catalogue.
  interestsFilter:  { type: [String], default: [] },
```

`flame/routes/users.js`, in `preferencesSchema` — add the import at the top of the file and the field:

```js
const { INTEREST_TOKENS, MAX_INTEREST_FILTER } = require('../config/interests');
```
```js
    // Validated against the catalogue because we control this input: it comes
    // from a multi-select, not free text. Stored user.interests are NOT
    // constrained by it — registration accepts free strings, so older accounts
    // may hold tokens outside the catalogue.
    interests_filter: z.array(z.enum(INTEREST_TOKENS)).max(MAX_INTEREST_FILTER).optional(),
```

`flame/controllers/userController.js`, in the `updatePreferences` mapping:

```js
    interestsFilter: b.interests_filter,
```

`flame/services/userService.js:97-99`:

```js
const PREFERENCE_FIELDS = new Set([
  'minAge', 'maxAge', 'maxDistance', 'showDistance', 'showOnlineStatus',
  'interestsFilter',
]);
```

- [ ] **Step 5: Apply the filter**

In `discover()`, after the distance block:

```js
  // Any overlap, not all: requiring every selected interest empties the deck on
  // a small user base, and this app has a small user base.
  const interestsFilter = prefs.interestsFilter;
  if (Array.isArray(interestsFilter) && interestsFilter.length > 0) {
    filter.interests = { $in: interestsFilter };
  }
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
node --test flame/__tests__/discoverFilters.test.js
node --test flame/__tests__/users.test.js
```
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add flame/config/interests.js flame/models/User.js flame/routes/users.js \
        flame/controllers/userController.js flame/services/userService.js \
        flame/services/discoveryService.js flame/__tests__/discoverFilters.test.js
git commit -m "feat(discover): filter by interests, on any overlap

preferences.interestsFilter is new and distinct from the user's own interests —
empty means no filter, which is why it defaults to [] and not to the whole
catalogue.

Any overlap rather than all: requiring every selected interest empties the deck
on a small user base.

config/interests.js is the canonical token vocabulary. The tokens are English
and stable on purpose — the app localises each token's LABEL and never the token,
so translating the UI cannot break a filter. The filter input is validated
against the catalogue because it comes from a multi-select; stored user.interests
are deliberately NOT constrained, since registration accepts free strings and
older accounts may hold tokens outside it."
```

---

## Task 4: Backend — serve the deck's head

**Repo:** backend

**Files:**
- Modify: `flame/routes/discovery.js`
- Modify: `flame/services/discoveryService.js` (`discover`)
- Test: `flame/__tests__/discoverFilters.test.js` (append)

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: `GET /discover?limit=N` with no `offset` returns `{ users, pagination: { limit, has_more } }`. With `offset` it returns today's shape including `total` and `offset`.

- [ ] **Step 1: Write the failing test**

Append to `flame/__tests__/discoverFilters.test.js`:

```js
test('the head path omits total and derives has_more from a full page', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'head-me@x.com', {});
  for (let i = 0; i < 3; i++) {
    await makeUser(app, `head${i}@x.com`, { gender: 'male' });
  }

  const res = await request(app).get(`${P}/discover?limit=2`)
    .set({ Authorization: `Bearer ${me.token}` }).expect(200);

  assert.equal(res.body.data.users.length, 2);
  assert.equal(res.body.data.pagination.has_more, true);
  assert.equal(res.body.data.pagination.total, undefined,
    'a response must not carry a field it did not compute');
  assert.equal(res.body.data.pagination.offset, undefined);
});

test('the legacy offset path is unchanged', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'legacy-me@x.com', {});
  for (let i = 0; i < 3; i++) {
    await makeUser(app, `legacy${i}@x.com`, { gender: 'male' });
  }

  const res = await request(app).get(`${P}/discover?limit=2&offset=1`)
    .set({ Authorization: `Bearer ${me.token}` }).expect(200);

  assert.equal(res.body.data.pagination.total, 3);
  assert.equal(res.body.data.pagination.offset, 1);
});

test('swiping then refetching the head never skips a profile', async () => {
  const app = freshApp();
  const me = await makeUser(app, 'drift-me@x.com', {});
  const auth = { Authorization: `Bearer ${me.token}` };
  const made = [];
  for (let i = 0; i < 6; i++) {
    made.push(await makeUser(app, `drift${i}@x.com`, { gender: 'male' }));
  }

  const seen = new Set();
  for (let round = 0; round < 3; round++) {
    const page = await request(app).get(`${P}/discover?limit=2`)
      .set(auth).expect(200);
    for (const u of page.body.data.users) {
      assert.ok(!seen.has(u.id), `profile ${u.name} served twice`);
      seen.add(u.id);
      // Swipe it, so the server excludes it from the next head.
      await request(app).post(`${P}/swipes`).set(auth)
        .send({ target_user_id: u.id, action: 'pass' }).expect(201);
    }
  }

  assert.equal(seen.size, 6,
    'every profile must be served exactly once — under skip(offset) the growing '
    + 'excluded set made page two step over profiles never seen');
});
```

Check the swipe route's path and body shape first with
`grep -n "router.post" flame/routes/swipes.js` and
`grep -n "z.object" -A 4 flame/routes/swipes.js`, and use the real ones.

- [ ] **Step 2: Run test to verify it fails**

```bash
node --test flame/__tests__/discoverFilters.test.js
```
Expected: FAIL — `total` is always present; the drift test skips profiles.

- [ ] **Step 3: Make the count conditional in the service**

At the end of `discover()`, replace the count-and-fetch with:

```js
  // Head path: no offset means "the next unseen profiles", which — because the
  // filter already excludes everyone swiped — is simply the first `limit` of the
  // filtered set. There is nothing to page past, so there is nothing to count.
  if (!offset) {
    const users = await User.find(filter).sort({ lastActive: -1 }).limit(limit + 1);
    const hasMore = users.length > limit;
    return {
      users: users.slice(0, limit).map((u) => toDiscoverUser(u, me)),
      hasMore,
    };
  }

  // Legacy offset path, for installed clients. It alone still pays for `total`,
  // because it alone ever reported it. It also keeps the skipping behaviour those
  // clients already have: ignoring their offset would give them duplicate cards
  // instead, which is a visible malfunction rather than an invisible one.
  const total = await User.countDocuments(filter);
  const users = await User.find(filter).sort({ lastActive: -1 }).skip(offset).limit(limit);
  return { users: users.map((u) => toDiscoverUser(u, me)), total };
```

- [ ] **Step 4: Make offset optional in the route**

Replace the handler body in `flame/routes/discovery.js`:

```js
router.get('/', auth, asyncHandler(async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit, 10) || 10, 50);
  // Absent, not defaulted: the head path is chosen by the ABSENCE of an offset,
  // so `|| 0` here would make it unreachable.
  const offset = req.query.offset === undefined
    ? undefined
    : (parseInt(req.query.offset, 10) || 0);

  const { users, total, hasMore } = await discoveryService.discover(req.user.id, { limit, offset });

  const pagination = { limit, has_more: hasMore ?? (offset + users.length < total) };
  if (total !== undefined) {
    pagination.total = total;
    pagination.offset = offset;
  }
  res.json({ success: true, data: { users, pagination } });
}));
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
node --test flame/__tests__/discoverFilters.test.js
node --test flame/__tests__/discoveryExclusion.test.js
node --test flame/__tests__/swipeRoutes.test.js
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add flame/routes/discovery.js flame/services/discoveryService.js flame/__tests__/discoverFilters.test.js
git commit -m "feat(discover): serve the deck's head instead of an offset page

skip(offset) paged over a filter that excludes everyone already swiped, so the
result set shrank beneath the offset and page two stepped over profiles the user
had never seen. A test now swipes through six profiles two at a time and asserts
each is served exactly once.

No cursor, because a cursor cannot work here either: the deck sorts by
lastActive, which moves every time someone opens the app, so a keyset cursor over
it is unstable by construction. Offset paging over a shrinking set is broken;
cursor paging over a moving sort key is also broken. Not paging is neither — the
server already excludes what you have swiped, so the head IS the next page.

The head path drops countDocuments and derives has_more from a limit+1 probe. The
offset path is untouched for installed clients: ignoring their offset would give
them duplicate cards, which is worse than the skipping they already have.

offset is now absent rather than defaulted to 0 in the route, since the head path
is selected by its absence."
```

---

## Task 5: App — shared interest catalogue

**Repo:** app

**Files:**
- Create: `lib/core/interests/interest_catalogue.dart`
- Modify: `lib/screens/auth/registration/steps/step_bio_interests.dart`
- Modify: `lib/l10n/app_en.arb` + 12 siblings
- Test: `test/core/interests/interest_catalogue_test.dart` (create)

**Interfaces:**
- Consumes: Task 3's `INTEREST_TOKENS`.
- Produces:

```dart
class Interest {
  final String token;      // stored value; matches the backend $in
  final IconData icon;
  final Color color;
  String label(AppLocalizations l10n);
}

const List<Interest> kInterests = [...];
Interest? interestFor(String token);
```

- [ ] **Step 1: Write the failing test**

Create `test/core/interests/interest_catalogue_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/interests/interest_catalogue.dart';
import 'package:flame/l10n/gen/app_localizations.dart';

void main() {
  test('tokens are unique and non-empty', () {
    final tokens = kInterests.map((i) => i.token).toList();
    expect(tokens.toSet().length, tokens.length);
    expect(tokens.any((t) => t.trim().isEmpty), isFalse);
  });

  test('every token has a localised label in English and Korean', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));

    for (final interest in kInterests) {
      expect(interest.label(en).trim(), isNotEmpty,
          reason: '${interest.token} has no English label');
      expect(interest.label(ko).trim(), isNotEmpty,
          reason: '${interest.token} has no Korean label');
    }
  });

  test('labels are translated, not echoed tokens', () async {
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));
    final travel = interestFor('Travel')!;

    expect(travel.label(ko), isNot('Travel'),
        reason: 'a Korean user must not read the stored English token');
  });

  test('interestFor returns null for an unknown token', () {
    // Registration accepts free-text interests, so stored values may be
    // off-catalogue. Callers must be able to detect that rather than crash.
    expect(interestFor('NotAnInterest'), isNull);
  });

  test('the catalogue matches the backend token list', () {
    // Kept in sync by hand across two repos; this is the tripwire.
    const backendTokens = [
      'Travel', 'Music', 'Movies', 'Sports', 'Fitness', 'Food', 'Art', 'Gaming',
      'Reading', 'Photography', 'Coffee', 'Hiking', 'Dancing', 'Cooking',
    ];
    expect(kInterests.map((i) => i.token).toList(), backendTokens,
        reason: 'update flame/config/interests.js in the backend repo too');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/interests/interest_catalogue_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Add the ARB labels**

Add to `lib/l10n/app_en.arb` one key per token, named `interestTravel`,
`interestMusic`, `interestMovies`, `interestSports`, `interestFitness`,
`interestFood`, `interestArt`, `interestGaming`, `interestReading`,
`interestPhotography`, `interestCoffee`, `interestHiking`, `interestDancing`,
`interestCooking` — English values equal to the token. Add the same 14 keys with
translated values to all 12 sibling ARBs. Then `flutter gen-l10n`.

- [ ] **Step 4: Write the catalogue**

Create `lib/core/interests/interest_catalogue.dart`:

```dart
import 'package:flutter/material.dart';

import 'package:flame/l10n/gen/app_localizations.dart';

/// One interest: a stable stored token, a localised label, and its chip styling.
///
/// The token is what `user.interests` stores and what the backend's discovery
/// `$in` matches. It is English and never translated — translating it would
/// silently break every stored value and every filter. Only [label] varies by
/// locale.
class Interest {
  const Interest(this.token, this.icon, this.color, this._label);

  final String token;
  final IconData icon;
  final Color color;
  final String Function(AppLocalizations) _label;

  String label(AppLocalizations l10n) => _label(l10n);
}

/// The canonical vocabulary. Mirrored in the backend's `flame/config/interests.js`;
/// `test/core/interests/interest_catalogue_test.dart` is the tripwire for drift.
///
/// Replaces two hardcoded lists — `allInterests` in the filter sheet and
/// `_InterestItem` in the registration step — which would have drifted apart and
/// left an interests filter whose vocabulary did not match what users had picked.
const List<Interest> kInterests = [
  Interest('Travel', Icons.flight_takeoff_rounded, Color(0xFF3498DB), _travel),
  Interest('Music', Icons.music_note_rounded, Color(0xFF9B59B6), _music),
  Interest('Movies', Icons.movie_rounded, Color(0xFFE74C3C), _movies),
  Interest('Sports', Icons.sports_soccer_rounded, Color(0xFF27AE60), _sports),
  Interest('Fitness', Icons.fitness_center_rounded, Color(0xFFE67E22), _fitness),
  Interest('Food', Icons.restaurant_rounded, Color(0xFFF39C12), _food),
  Interest('Art', Icons.palette_rounded, Color(0xFF16A085), _art),
  Interest('Gaming', Icons.sports_esports_rounded, Color(0xFF8E44AD), _gaming),
  Interest('Reading', Icons.menu_book_rounded, Color(0xFF2980B9), _reading),
  Interest('Photography', Icons.camera_alt_rounded, Color(0xFFD35400), _photography),
  Interest('Coffee', Icons.coffee_rounded, Color(0xFF795548), _coffee),
  Interest('Hiking', Icons.terrain_rounded, Color(0xFF00897B), _hiking),
  Interest('Dancing', Icons.music_video_rounded, Color(0xFFC2185B), _dancing),
  Interest('Cooking', Icons.soup_kitchen_rounded, Color(0xFFEF6C00), _cooking),
];

String _travel(AppLocalizations l) => l.interestTravel;
String _music(AppLocalizations l) => l.interestMusic;
String _movies(AppLocalizations l) => l.interestMovies;
String _sports(AppLocalizations l) => l.interestSports;
String _fitness(AppLocalizations l) => l.interestFitness;
String _food(AppLocalizations l) => l.interestFood;
String _art(AppLocalizations l) => l.interestArt;
String _gaming(AppLocalizations l) => l.interestGaming;
String _reading(AppLocalizations l) => l.interestReading;
String _photography(AppLocalizations l) => l.interestPhotography;
String _coffee(AppLocalizations l) => l.interestCoffee;
String _hiking(AppLocalizations l) => l.interestHiking;
String _dancing(AppLocalizations l) => l.interestDancing;
String _cooking(AppLocalizations l) => l.interestCooking;

/// The catalogue entry for [token], or null when it is off-catalogue.
///
/// Registration accepts free-text interests, so a stored value may not be here.
/// Callers render such a value as its raw token rather than dropping it.
Interest? interestFor(String token) {
  for (final i in kInterests) {
    if (i.token == token) return i;
  }
  return null;
}
```

Use the exact icons and colours already in `step_bio_interests.dart` for the
tokens it defines, so registration looks unchanged.

- [ ] **Step 5: Point the registration step at the catalogue**

In `step_bio_interests.dart`, delete the private `_InterestItem` list and read
`kInterests`, rendering `interest.label(context.l10n)` instead of the literal and
storing `interest.token`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter test test/core/interests/ test/screens/auth/step_bio_interests_test.dart test/l10n/`
Expected: PASS.

- [ ] **Step 7: Verify and commit**

```bash
flutter analyze
flutter test
git add lib/core/interests/ lib/screens/auth/registration/steps/step_bio_interests.dart \
        lib/l10n/ test/core/interests/
git commit -m "feat(interests): one catalogue, with translatable labels over stable tokens

There were two hardcoded interest lists — allInterests in the filter sheet and
_InterestItem in the registration step. They would have drifted, and an interests
filter whose vocabulary differs from what users actually picked matches nothing.

The token is the stored value and the thing the backend's \$in matches; it stays
English and untranslated, because translating it would break every stored value
and every filter at once. Only the label is localised, across all thirteen
locales — a Korean user previously read 'Travel'.

A test pins the catalogue against the backend's config/interests.js by value.
Two hardcoded lists in two repos is the situation; a tripwire is the best
available answer to it."
```

---

## Task 6: App — nullable distance with a locale-appropriate unit

**Files:**
- Create: `lib/core/format/distance_display.dart`
- Modify: `lib/models/user.dart:12,46,134,266`
- Modify: `lib/widgets/profile_card.dart:199`
- Modify: `lib/screens/profile/profile_detail_screen.dart:165`
- Modify: `lib/l10n/app_en.arb` + 12 siblings
- Test: `test/core/format/distance_display_test.dart` (create)
- Test: `test/models/user_distance_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `String formatDistanceAway(double km, AppLocalizations l10n, String localeName)`. `User.distance` becomes `double?`; `User.distanceText` becomes `String?`.

- [ ] **Step 1: Write the failing test**

Create `test/core/format/distance_display_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/format/distance_display.dart';
import 'package:flame/l10n/gen/app_localizations.dart';

void main() {
  late AppLocalizations en;
  late AppLocalizations ko;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ko = await AppLocalizations.delegate.load(const Locale('ko'));
  });

  test('US English reads in miles', () {
    // 16 km is about 10 miles. "16 km away" is wrong for a US reader in a way a
    // translation alone would not fix.
    final text = formatDistanceAway(16, en, 'en_US');
    expect(text, contains('10'));
    expect(text.toLowerCase(), contains('mi'));
  });

  test('metric locales read in kilometres', () {
    expect(formatDistanceAway(16, ko, 'ko'), contains('16'));
    expect(formatDistanceAway(16, en, 'en_GB'), contains('16'));
  });

  test('under a kilometre is not rounded to zero', () {
    final text = formatDistanceAway(0.4, ko, 'ko');
    expect(text, isNot(contains('0 ')),
        reason: 'rounding to "0 km away" is the bug we are removing');
  });

  test('a large distance is not rendered with decimals', () {
    expect(formatDistanceAway(344.29, ko, 'ko'), contains('344'));
    expect(formatDistanceAway(344.29, ko, 'ko'), isNot(contains('.')));
  });
}
```

Create `test/models/user_distance_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';

Map<String, dynamic> _json(Object? distance) => {
      'id': 'u1', 'name': 'A', 'photos': <dynamic>[],
      if (distance != null) 'distance': distance,
    };

void main() {
  test('a missing distance is unknown, not zero', () {
    expect(User.fromJson(_json(null)).distance, isNull);
  });

  test('an explicit null is unknown', () {
    expect(User.fromJson({..._json(null), 'distance': null}).distance, isNull);
  });

  test('zero is treated as unknown', () {
    // A server that has not deployed the real computation still sends 0. A
    // genuine 0 km means standing on the exact same point, so treating it as
    // unknown costs nothing and removes "0 km away" before the deploy lands.
    expect(User.fromJson(_json(0)).distance, isNull);
  });

  test('a real distance survives', () {
    expect(User.fromJson(_json(12.5)).distance, 12.5);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/core/format/distance_display_test.dart test/models/user_distance_test.dart`
Expected: FAIL — the file does not exist; `distance` is non-nullable and defaults to 0.

- [ ] **Step 3: Add the ARB keys**

Add to `lib/l10n/app_en.arb` and all 12 siblings:

```json
"distanceAwayKm": "{value} km away",
"@distanceAwayKm": {
  "description": "Distance to another user, metric",
  "placeholders": { "value": { "type": "String" } }
},
"distanceAwayMiles": "{value} mi away",
"@distanceAwayMiles": {
  "description": "Distance to another user, imperial",
  "placeholders": { "value": { "type": "String" } }
}
```

Then `flutter gen-l10n`.

- [ ] **Step 4: Write the formatter**

Create `lib/core/format/distance_display.dart`:

```dart
import 'package:intl/intl.dart';

import 'package:flame/l10n/gen/app_localizations.dart';

/// Locales that read distance in miles rather than kilometres.
///
/// The wire is always kilometres; this is display only. A US reader seeing
/// "16 km away" is a bug that no amount of translating the word "away" fixes.
const _imperialLocales = {'en_US', 'en-US', 'my', 'en_LR', 'en-LR'};

const double _kmPerMile = 1.609344;

/// "10 mi away" / "16 km away", in [l10n]'s language and [localeName]'s units.
String formatDistanceAway(double km, AppLocalizations l10n, String localeName) {
  final imperial = _imperialLocales.contains(localeName);
  final value = imperial ? km / _kmPerMile : km;

  // One decimal below the unit, none above: "0.4 km away" is useful and
  // "344.3 km away" is noise — and rounding the first to "0 km away" is exactly
  // the fabricated label this replaces.
  final pattern = value < 1 ? '0.#' : '0';
  final text = NumberFormat(pattern, localeName).format(value);

  return imperial ? l10n.distanceAwayMiles(text) : l10n.distanceAwayKm(text);
}
```

- [ ] **Step 5: Make `User.distance` nullable**

In `lib/models/user.dart`:

```dart
  /// Kilometres to this user, or null when unknown — either side missing a
  /// location, or this user having turned `showDistance` off.
  final double? distance;
```
```dart
    this.distance,
```
```dart
      // Zero is treated as unknown: a server that has not deployed the real
      // computation still sends 0, and a genuine 0 km means standing on the
      // exact same point. Reading it as unknown removes "0 km away" without
      // waiting for the deploy.
      distance: (json['distance'] as num?)?.toDouble() == 0
          ? null
          : (json['distance'] as num?)?.toDouble(),
```

Replace the getter:

```dart
  /// Null when there is no distance to show, so callers omit the row entirely
  /// rather than rendering a placeholder number.
  String? distanceTextFor(AppLocalizations l10n, String localeName) {
    final km = distance;
    if (km == null) return null;
    return formatDistanceAway(km, l10n, localeName);
  }
```

Delete `distanceText`.

- [ ] **Step 6: Fix the two call sites**

`profile_card.dart:199` and `profile_detail_screen.dart:165` currently render
`widget.user.distanceText` unconditionally. Both become conditional:

```dart
    final distance = widget.user.distanceTextFor(
      context.l10n, Localizations.localeOf(context).toString());
```

and the widget that displayed it is wrapped in `if (distance != null)`. In
`profile_detail_screen.dart` the string is `'${widget.user.location} - ${widget.user.distanceText}'`,
which becomes the location alone when distance is null — no dangling separator.

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/core/format/ test/models/ test/l10n/`
Expected: PASS.

- [ ] **Step 8: Verify and commit**

```bash
flutter analyze
flutter test
git add lib/core/format/distance_display.dart lib/models/user.dart \
        lib/widgets/profile_card.dart lib/screens/profile/profile_detail_screen.dart \
        lib/l10n/ test/core/format/ test/models/user_distance_test.dart
git commit -m "fix(discover): stop every card claiming '0 km away'

distance was a non-nullable double defaulting to 0 and distanceText could only
render a number, so the deck and the detail screen showed a fabricated distance
to every user. distance is nullable now and both call sites omit the row.

Zero counts as unknown. A server that has not deployed the real computation
still sends 0, and a genuine 0 km means standing on the exact same point — so
reading it as unknown removes the lie without waiting for the deploy.

The label was also hardcoded English AND hardcoded kilometres. The wire stays
metric; display converts, because a US reader seeing '16 km away' is a bug that
translating the word 'away' does not fix. Sub-kilometre distances keep one
decimal, since rounding 0.4 km to '0 km away' would reintroduce exactly what
this removes."
```

---

## Task 7: App — breakpoints helper

**Files:**
- Create: `lib/core/layout/breakpoints.dart`
- Test: `test/core/layout/breakpoints_test.dart` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: `enum WindowClass { compact, expanded }`, `WindowClass windowClassOf(BuildContext)`, `bool isCompact(BuildContext)`, `const double kDeckMaxWidth = 420`, `const double kSheetMaxWidth = 560`.

- [ ] **Step 1: Write the failing test**

Create `test/core/layout/breakpoints_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/layout/breakpoints.dart';

Future<WindowClass> classAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late WindowClass seen;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      seen = windowClassOf(context);
      return const SizedBox();
    }),
  ));
  return seen;
}

void main() {
  testWidgets('a phone is compact', (tester) async {
    expect(await classAt(tester, const Size(390, 844)), WindowClass.compact);
  });

  testWidgets('599 is still compact and 600 is expanded', (tester) async {
    expect(await classAt(tester, const Size(599, 900)), WindowClass.compact);
    expect(await classAt(tester, const Size(600, 900)), WindowClass.expanded);
  });

  testWidgets('a tablet is expanded', (tester) async {
    expect(await classAt(tester, const Size(834, 1112)), WindowClass.expanded);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/layout/breakpoints_test.dart`
Expected: FAIL — the file does not exist.

- [ ] **Step 3: Write the helper**

Create `lib/core/layout/breakpoints.dart`:

```dart
import 'package:flutter/widgets.dart';

/// Window size classes, following Material's own breakpoints.
///
/// Two, not three: this app has one phone layout and one "wider than a phone"
/// layout. A medium class would be invented rather than needed, and an unused
/// breakpoint is a decision nobody has actually made.
enum WindowClass { compact, expanded }

/// Material's compact/medium boundary.
const double kExpandedBreakpoint = 600;

/// The swipe deck's ceiling. A full-bleed card on a tablet is absurd — the deck
/// stays phone-sized and centres itself.
const double kDeckMaxWidth = 420;

/// The filter sheet's ceiling on wide screens, so form rows do not stretch into
/// unreadably long lines.
const double kSheetMaxWidth = 560;

WindowClass windowClassOf(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kExpandedBreakpoint
        ? WindowClass.compact
        : WindowClass.expanded;

bool isCompact(BuildContext context) =>
    windowClassOf(context) == WindowClass.compact;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/layout/breakpoints_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify and commit**

```bash
flutter analyze
flutter test
git add lib/core/layout/ test/core/layout/
git commit -m "feat(layout): a first breakpoint helper

Three files in the whole app used any responsive primitive and there was no
breakpoint anywhere. Two size classes following Material's own boundary, plus the
two max-widths Scope A needs — a full-bleed swipe card on a tablet is absurd, and
form rows stretched across 1000 pixels are unreadable.

Two classes rather than three on purpose: a medium class would be invented rather
than needed, and an unused breakpoint is a decision nobody has made."
```

---

## Task 8: App — service and result shape

**Files:**
- Modify: `lib/services/discovery_service.dart`
- Modify: `lib/services/user_service.dart:97-110`
- Test: `test/services/discovery_service_test.dart` (create)

**Interfaces:**
- Consumes: Task 4's contract.
- Produces: `getPotentialMatches({int limit = 10})` — no `offset`. `DiscoveryResult({required List<User> users, required bool hasMore})` — `total` and `offset` removed. `UserService.updatePreferences({..., List<String>? interestsFilter})` sends `interests_filter`.

- [ ] **Step 1: Write the failing test**

Create `test/services/discovery_service_test.dart` following the `_MockClient`
pattern in `test/services/chat_service_test.dart`:

```dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'access_token': 'token', 'refresh_token': 'refresh',
    });
  });

  test('no offset is sent at all', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({'success': true, 'data': {'users': [], 'pagination': {'has_more': false}}}),
      200,
    ));
    final api = ApiClient.testInstance(httpClient: mock);
    await api.init();

    await DiscoveryService(apiClient: api).getPotentialMatches(limit: 10);

    final url = mock.calls.single.url;
    expect(url.queryParameters['limit'], '10');
    expect(url.queryParameters.containsKey('offset'), isFalse,
        reason: 'the head path is selected by the absence of an offset');
  });

  test('hasMore comes from the response', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'success': true,
        'data': {
          'users': [{'id': 'u1', 'name': 'A', 'photos': <dynamic>[]}],
          'pagination': {'has_more': true},
        },
      }),
      200,
    ));
    final api = ApiClient.testInstance(httpClient: mock);
    await api.init();

    final result = await DiscoveryService(apiClient: api).getPotentialMatches();

    expect(result.data!.users.single.id, 'u1');
    expect(result.data!.hasMore, isTrue);
  });

  test('a missing has_more reads as no more', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({'success': true, 'data': {'users': []}}), 200));
    final api = ApiClient.testInstance(httpClient: mock);
    await api.init();

    expect((await DiscoveryService(apiClient: api).getPotentialMatches()).data!.hasMore,
        isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/services/discovery_service_test.dart`
Expected: FAIL — `DiscoveryService` has no injectable `apiClient` and still sends `offset`.

- [ ] **Step 3: Rewrite the service**

Replace `lib/services/discovery_service.dart`:

```dart
import 'package:flame/models/user.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/user_service.dart';

class DiscoveryService {
  DiscoveryService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  /// The next unseen profiles.
  ///
  /// Sends no offset. The server excludes everyone already swiped, so the head
  /// of the filtered set IS the next page — and paging it with an offset made the
  /// deck step over profiles as that excluded set grew. Filters live in user
  /// preferences and are applied server-side.
  Future<ServiceResult<DiscoveryResult>> getPotentialMatches({int limit = 10}) async {
    final response = await _apiClient.get(
      '/discover',
      queryParams: {'limit': limit.toString()},
    );

    if (response.success && response.data != null) {
      final usersData = response.data['users'] as List? ?? [];
      final pagination = response.data['pagination'] as Map<String, dynamic>? ?? {};

      return ServiceResult.success(DiscoveryResult(
        users: usersData.map((u) => User.fromJson(u)).toList(),
        hasMore: pagination['has_more'] ?? false,
      ));
    }

    return ServiceResult.failure(response.error ?? 'Failed to get potential matches');
  }
}

/// `total` and `offset` are deliberately absent: both existed only to serve
/// offset paging, the head path does not compute them, and keeping them as
/// `?? users.length` fallbacks would let a caller read a plausible-looking
/// number that means nothing.
class DiscoveryResult {
  const DiscoveryResult({required this.users, required this.hasMore});

  final List<User> users;
  final bool hasMore;
}
```

- [ ] **Step 4: Add `interestsFilter` to `updatePreferences`**

In `lib/services/user_service.dart`, add the parameter and body field:

```dart
    List<String>? interestsFilter,
```
```dart
    if (interestsFilter != null) body['interests_filter'] = interestsFilter;
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/services/`
Expected: PASS.

- [ ] **Step 6: Verify and commit**

Analyze will fail here on `discovery_provider.dart`, which still reads `total`
and `offset`. That is Task 9, in the same session.

```bash
git add lib/services/discovery_service.dart lib/services/user_service.dart \
        test/services/discovery_service_test.dart
git commit -m "refactor(discover): the service stops paging and stops inventing totals

No offset is sent. The server excludes everyone swiped, so the head of the
filtered set is the next page — and paging it with an offset is what made the deck
skip profiles as that excluded set grew.

DiscoveryResult drops total and offset. Both existed only to serve offset paging;
the head path does not compute them, and leaving them as '?? users.length'
fallbacks would let a caller read a plausible number that means nothing.

updatePreferences gains interestsFilter. The provider is fixed in the next
commit; analyze is red in between."
```

---

## Task 9: App — `refill()` replaces `loadMore()`

**Files:**
- Modify: `lib/providers/discovery_provider.dart`
- Test: `test/providers/discovery_refill_test.dart` (create)

**Interfaces:**
- Consumes: Task 8's `DiscoveryResult`.
- Produces: `DiscoveryNotifier.load({bool refresh = false})`, `.refill()`, `.removeUser(String)`, `.undoRemove(User)`, `.clearAndReload()`. `bool get hasMore`.

- [ ] **Step 1: Write the failing test**

Create `test/providers/discovery_refill_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/discovery_provider.dart';
import 'package:flame/services/discovery_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

User _u(String id) => User.fromJson({'id': id, 'name': id, 'photos': <dynamic>[]});

class _Service extends DiscoveryService {
  _Service(this.pages);
  final List<List<String>> pages;
  int calls = 0;
  bool fail = false;
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<ServiceResult<DiscoveryResult>> getPotentialMatches({int limit = 10}) async {
    inFlight++;
    maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
    await Future<void>.delayed(Duration.zero);
    inFlight--;

    if (fail) return ServiceResult.failure('offline');
    final page = calls < pages.length ? pages[calls] : <String>[];
    calls++;
    return ServiceResult.success(
      DiscoveryResult(users: page.map(_u).toList(), hasMore: page.isNotEmpty));
  }
}

void main() {
  test('load stores the first page', () async {
    final n = DiscoveryNotifier(_Service([['a', 'b']]));

    await n.load();

    expect(n.state.value!.map((u) => u.id), ['a', 'b']);
  });

  test('refill appends only profiles not already held', () async {
    // The head necessarily re-includes anything fetched but not yet swiped.
    final n = DiscoveryNotifier(_Service([['a', 'b'], ['b', 'c']]));
    await n.load();

    await n.refill();

    expect(n.state.value!.map((u) => u.id), ['a', 'b', 'c']);
  });

  test('concurrent refills make one request', () async {
    final service = _Service([['a'], ['b']]);
    final n = DiscoveryNotifier(service);
    await n.load();

    await Future.wait([n.refill(), n.refill(), n.refill()]);

    expect(service.maxInFlight, 1,
        reason: 'the notifier had no in-flight guard, so a double fire '
            'advanced the offset twice and appended without deduping');
  });

  test('a failed refill keeps the deck', () async {
    final service = _Service([['a', 'b']]);
    final n = DiscoveryNotifier(service);
    await n.load();

    service.fail = true;
    await n.refill();

    expect(n.state.value!.map((u) => u.id), ['a', 'b']);
  });

  test('a failed initial load is an error, not an empty deck', () async {
    final service = _Service([])..fail = true;
    final n = DiscoveryNotifier(service);

    await n.load();

    expect(n.state.hasError, isTrue);
    expect(n.state.valueOrNull, isNull,
        reason: 'an error must never render as "you have seen everyone"');
  });

  test('an empty first page is an empty deck, not an error', () async {
    final n = DiscoveryNotifier(_Service([[]]));

    await n.load();

    expect(n.state.hasError, isFalse);
    expect(n.state.value, isEmpty);
    expect(n.hasMore, isFalse);
  });

  test('removeUser drops one card and undoRemove puts it back in front', () async {
    final n = DiscoveryNotifier(_Service([['a', 'b']]));
    await n.load();
    final first = n.state.value!.first;

    n.removeUser('a');
    expect(n.state.value!.map((u) => u.id), ['b']);

    n.undoRemove(first);
    expect(n.state.value!.map((u) => u.id), ['a', 'b']);
  });

  test('clearAndReload empties before refetching', () async {
    // Applying changed filters cannot merge: the cards already held were chosen
    // under the old predicate, so keeping them shows results the new filters
    // exclude, which reads as the filter not working.
    final service = _Service([['a', 'b'], ['c']]);
    final n = DiscoveryNotifier(service);
    await n.load();

    await n.clearAndReload();

    expect(n.state.value!.map((u) => u.id), ['c']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/discovery_refill_test.dart`
Expected: FAIL — `DiscoveryNotifier` takes no service in that shape, has no
`refill`, no `clearAndReload`, and reads `total`/`offset`.

- [ ] **Step 3: Rewrite the notifier**

Replace the body of `lib/providers/discovery_provider.dart`:

```dart
final discoveryServiceProvider = Provider<DiscoveryService>((ref) => DiscoveryService());

final discoveryProvider =
    StateNotifierProvider<DiscoveryNotifier, AsyncValue<List<User>>>((ref) {
  return DiscoveryNotifier(ref.watch(discoveryServiceProvider));
});

/// The swipe deck.
///
/// There is no offset. The server excludes everyone already swiped, so the head
/// of the filtered set is always the next unseen page — which is why [refill]
/// dedupes rather than paging: the head necessarily re-includes anything already
/// fetched but not yet swiped.
class DiscoveryNotifier extends StateNotifier<AsyncValue<List<User>>> {
  DiscoveryNotifier(this._service) : super(const AsyncValue.loading());

  final DiscoveryService _service;

  static const int pageSize = 10;

  bool _hasMore = true;
  bool _fetching = false;

  bool get hasMore => _hasMore;

  /// Fetches the head, replacing the deck. Used on first open and on retry.
  Future<void> load({bool refresh = false}) async {
    if (refresh) state = const AsyncValue.loading();
    _fetching = true;
    final result = await _service.getPotentialMatches(limit: pageSize);
    _fetching = false;

    if (!mounted) return;
    if (!result.success || result.data == null) {
      // Distinct from an empty deck on purpose: an error must never render as
      // "you have seen everyone".
      state = AsyncValue.error(
          ErrorStringsFor.fromString(result.error), StackTrace.current);
      return;
    }
    _hasMore = result.data!.hasMore;
    state = AsyncValue.data(result.data!.users);
  }

  /// Tops the deck up. Keeps what is already held on failure.
  Future<void> refill() async {
    if (_fetching || !_hasMore) return;
    _fetching = true;
    final result = await _service.getPotentialMatches(limit: pageSize);
    _fetching = false;

    if (!mounted) return;
    if (!result.success || result.data == null) return;

    _hasMore = result.data!.hasMore;
    final held = state.valueOrNull ?? const <User>[];
    final heldIds = held.map((u) => u.id).toSet();
    final fresh = result.data!.users.where((u) => !heldIds.contains(u.id));
    state = AsyncValue.data([...held, ...fresh]);
  }

  /// Applies changed filters. Cannot merge — the cards already held were chosen
  /// under the old predicate, so keeping them would show results the new filters
  /// exclude, which reads as the filter not working.
  Future<void> clearAndReload() async {
    state = const AsyncValue.data(<User>[]);
    _hasMore = true;
    await load(refresh: true);
  }

  void removeUser(String userId) {
    final current = state.valueOrNull ?? const <User>[];
    state = AsyncValue.data(current.where((u) => u.id != userId).toList());
  }

  void undoRemove(User user) {
    final current = state.valueOrNull ?? const <User>[];
    state = AsyncValue.data([user, ...current]);
  }

  User? get currentUser => (state.valueOrNull ?? const <User>[]).firstOrNull;
}
```

Keep `currentCardIndexProvider` as it is.

- [ ] **Step 4: Update the deck's call sites**

`lib/screens/home/home_screen.dart` calls `loadPotentialMatches` and `loadMore`.
Point them at `load` and `refill`, and trigger `refill()` when fewer than three
cards remain after a swipe.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: analyze 0 errors / 0 warnings, tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/discovery_provider.dart lib/screens/home/home_screen.dart \
        test/providers/discovery_refill_test.dart
git commit -m "fix(discover): refill the deck by deduping, not by paging

loadMore advanced an offset over a filter that excludes everyone swiped, so the
result set shrank beneath it and the deck stepped over profiles never seen. It
also had no in-flight guard, so a double fire advanced the offset twice and
appended without deduping.

refill fetches the head and drops what is already held — the head necessarily
re-includes anything fetched but not yet swiped. Concurrent calls collapse to one
request, and a failed refill keeps the cards on screen.

clearAndReload exists for a filter change, which cannot merge: cards chosen under
the old predicate would show results the new filters exclude, and that reads as
the filter being broken.

A failed initial load is now an error state rather than an empty deck."
```

---

## Task 10: App — location refresh on Discover open

**Files:**
- Create: `lib/providers/location_provider.dart`
- Test: `test/providers/location_refresh_test.dart` (create)

**Interfaces:**
- Consumes: `LocationService.getCurrentPosition()` → `LocationResult` with `.success`, `.latitude`, `.longitude`, `.error`; `CurrentUserNotifier.updateLocation(double, double)`.
- Produces:

```dart
enum LocationAvailability { unknown, granted, denied }

class LocationRefresher {
  LocationRefresher({required LocationService service, required Future<bool> Function(double, double) push});
  LocationAvailability get availability;
  Future<void> refreshOnce();
}

final locationRefresherProvider = Provider<LocationRefresher>(...);
```

- [ ] **Step 1: Write the failing test**

Create `test/providers/location_refresh_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/providers/location_provider.dart';
import 'package:flame/services/location_service.dart';

class _Service extends LocationService {
  _Service({this.ok = true});
  final bool ok;
  int calls = 0;

  @override
  Future<LocationResult> getCurrentPosition() async {
    calls++;
    if (!ok) return LocationResult.failure('denied');
    return LocationResult.successAt(1.5, 2.5);
  }
}

void main() {
  test('a successful refresh pushes the coordinates once per session', () async {
    final service = _Service();
    final pushed = <List<double>>[];
    final r = LocationRefresher(
      service: service,
      push: (lat, lng) async { pushed.add([lat, lng]); return true; },
    );

    await r.refreshOnce();
    await r.refreshOnce();
    await r.refreshOnce();

    expect(service.calls, 1, reason: 'once per session, not once per open');
    expect(pushed, [[1.5, 2.5]]);
    expect(r.availability, LocationAvailability.granted);
  });

  test('a refusal is recorded and not retried', () async {
    final service = _Service(ok: false);
    var pushes = 0;
    final r = LocationRefresher(
      service: service,
      push: (_, __) async { pushes++; return true; },
    );

    await r.refreshOnce();
    await r.refreshOnce();

    expect(service.calls, 1, reason: 'asking on every open is nagging');
    expect(pushes, 0);
    expect(r.availability, LocationAvailability.denied,
        reason: 'the filter sheet disables the distance slider on this');
  });

  test('a failed push does not throw and does not block a later session',
      () async {
    final r = LocationRefresher(
      service: _Service(),
      push: (_, __) async => false,
    );

    await r.refreshOnce();

    expect(r.availability, LocationAvailability.granted,
        reason: 'the position was obtained; only the PATCH failed');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/location_refresh_test.dart`
Expected: FAIL — the provider does not exist, and `LocationResult.successAt` does not exist.

- [ ] **Step 3: Add the test-friendly constructor to `LocationResult`**

`LocationResult.success` currently takes a `Position`, which cannot be built in a
unit test without a platform channel. Add alongside it:

```dart
  /// Coordinates without a Position, so callers and tests that only need the
  /// pair are not forced to fabricate a platform object.
  factory LocationResult.successAt(double latitude, double longitude) => ...
```

Keep `latitude` and `longitude` readable from both constructors.

- [ ] **Step 4: Write the refresher**

Create `lib/providers/location_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/providers/user_provider.dart';
import 'package:flame/services/location_service.dart';

/// Whether we can offer distance-based filtering at all.
enum LocationAvailability { unknown, granted, denied }

/// Refreshes the stored location at most once per app session.
///
/// Registration requires location, so most accounts already have a point; this
/// keeps it current as people move. Deliberately fire-and-forget: location is
/// enrichment, and the deck must never wait on it or fail because of it.
///
/// Once per session rather than once per open, because asking on every open is
/// nagging and a refusal is a decision worth respecting until next launch.
class LocationRefresher {
  LocationRefresher({required LocationService service, required this.push})
      : _service = service;

  final LocationService _service;
  final Future<bool> Function(double latitude, double longitude) push;

  LocationAvailability _availability = LocationAvailability.unknown;
  bool _attempted = false;

  LocationAvailability get availability => _availability;

  Future<void> refreshOnce() async {
    if (_attempted) return;
    _attempted = true;

    final result = await _service.getCurrentPosition();
    if (!result.success || result.latitude == null || result.longitude == null) {
      _availability = LocationAvailability.denied;
      return;
    }

    _availability = LocationAvailability.granted;
    // The PATCH failing changes nothing the user can see: the point stored at
    // registration stands, and we try again next session.
    await push(result.latitude!, result.longitude!);
  }
}

final locationRefresherProvider = Provider<LocationRefresher>((ref) {
  return LocationRefresher(
    service: LocationService(),
    push: (lat, lng) =>
        ref.read(currentUserProvider.notifier).updateLocation(lat, lng),
  );
});
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/providers/location_refresh_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify and commit**

```bash
flutter analyze
flutter test
git add lib/providers/location_provider.dart lib/services/location_service.dart \
        test/providers/location_refresh_test.dart
git commit -m "feat(discover): refresh the stored location once per session

LocationService and CurrentUserNotifier.updateLocation both already existed and
had never been connected to anything, which is why maxDistance had nothing to
filter against.

Once per session, not once per open: asking repeatedly is nagging, and a refusal
is a decision worth respecting until the next launch. Fire-and-forget throughout —
location is enrichment, so the deck never waits on it and never fails because of
it. A failed PATCH leaves the point stored at registration in place.

The refusal is recorded rather than swallowed, because the filter sheet needs it
to disable the distance slider with a reason instead of offering a control that
cannot work."
```

---

## Task 11: App — rename so Discover means one thing

**Files:**
- Move: `lib/screens/home/home_screen.dart` → `lib/screens/discover/discover_screen.dart`
- Move: old `lib/screens/discover/discover_screen.dart` → `lib/screens/discover/discover_filters_screen.dart`
- Modify: `lib/main.dart:9,95`
- Modify: `lib/screens/main_shell.dart:11`
- Modify: any test importing either path

**Interfaces:**
- Consumes: nothing.
- Produces: `DiscoverScreen` (the deck) and `DiscoverFiltersScreen` (the sheet), route `/discover/filters`.

- [ ] **Step 1: Move the deck**

```bash
cd /Users/davis/Desktop/Personal/flame
git mv lib/screens/discover/discover_screen.dart lib/screens/discover/discover_filters_screen.dart
git mv lib/screens/home/home_screen.dart lib/screens/discover/discover_screen.dart
rmdir lib/screens/home 2>/dev/null || true
```

- [ ] **Step 2: Rename the classes and the route**

In `lib/screens/discover/discover_screen.dart`: `HomeScreen` → `DiscoverScreen`,
`_HomeScreenState` → `_DiscoverScreenState`.

In `lib/screens/discover/discover_filters_screen.dart`: `DiscoverScreen` →
`DiscoverFiltersScreen`, `_DiscoverScreenState` → `_DiscoverFiltersScreenState`.

In `lib/main.dart`: the import path, and `routes: {'/discover/filters': (context) => const DiscoverFiltersScreen()}`.

In the deck's app bar, `Navigator.pushNamed(context, '/discover')` becomes
`'/discover/filters'`.

Then fix every remaining reference:

```bash
grep -rn "home/home_screen\|HomeScreen" lib/ test/
```

- [ ] **Step 3: Run the suite**

Run: `flutter analyze && flutter test`
Expected: analyze 0 errors / 0 warnings, tests PASS.

- [ ] **Step 4: Commit**

```bash
git add -A lib/ test/
git commit -m "refactor(discover): Discover means one thing now

The tab labelled Discover rendered HomeScreen, while the file named
discover_screen.dart was the filter sheet — so the word meant different things
depending on which file you had open.

The deck is DiscoverScreen and the sheet is DiscoverFiltersScreen at
/discover/filters. No behaviour change."
```

---

## Task 12: App — rebuild the filter sheet

**Files:**
- Modify: `lib/screens/discover/discover_filters_screen.dart`
- Modify: `lib/providers/filter_provider.dart`
- Modify: `lib/config/env.dart` (delete `advancedFiltersEnabled`)
- Modify: `lib/l10n/app_en.arb` + 12 siblings
- Test: `test/screens/discover/discover_filters_test.dart` (create)

**Interfaces:**
- Consumes: Tasks 5, 7, 8, 10.
- Produces: `FilterNotifier.savePreferencesToApi()` persists age, distance, interests **and** `lookingFor`; `DiscoveryFilters` loses `onlineOnly`.

- [ ] **Step 1: Write the failing test**

Create `test/screens/discover/discover_filters_test.dart`. Assert:

```dart
  testWidgets('the distance slider is disabled, with a reason, without location',
      (tester) async {
    await pumpSheet(tester, availability: LocationAvailability.denied);
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull,
        reason: 'a control that cannot work must not look like one that can');
    expect(find.text(l10n.filterDistanceNeedsLocation), findsOneWidget);
  });

  testWidgets('the distance slider is live with location', (tester) async {
    await pumpSheet(tester, availability: LocationAvailability.granted);
    await tester.pumpAndSettle();

    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
  });

  testWidgets('a failed save keeps the sheet open and does not reload the deck',
      (tester) async {
    await pumpSheet(tester, saveSucceeds: false);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.filterApply));
    await tester.pumpAndSettle();

    expect(find.byType(DiscoverFiltersScreen), findsOneWidget,
        reason: 'it must not look saved when it is not');
    expect(deckReloads, 0);
  });

  testWidgets('a successful save clears and reloads the deck', (tester) async {
    await pumpSheet(tester, saveSucceeds: true);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.filterApply));
    await tester.pumpAndSettle();

    expect(deckReloads, 1);
  });

  testWidgets('interest chips wrap rather than overflow at 2x text scale',
      (tester) async {
    await pumpSheet(tester, textScale: 2.0);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet is width-constrained on a tablet', (tester) async {
    await pumpSheet(tester, size: const Size(1024, 1366));
    await tester.pumpAndSettle();

    final box = tester.getSize(find.byKey(const ValueKey('filters-body')));
    expect(box.width, lessThanOrEqualTo(kSheetMaxWidth));
  });
```

Write `pumpSheet` to override `locationRefresherProvider`, `filterProvider` and
`discoveryProvider` with fakes, set `tester.view.physicalSize` and
`tester.platformDispatcher.textScaleFactorTestValue`, and reset both in
`addTearDown`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/discover/discover_filters_test.dart`
Expected: FAIL — no gender or interests controls, no disabled state, no key.

- [ ] **Step 3: Add the ARB keys**

`filterTitle`, `filterReset`, `filterApply`, `filterAgeRange`, `filterDistance`,
`filterDistanceNeedsLocation`, `filterShowMe`, `filterEveryone`,
`filterInterests`, `filterSaveFailed`, `deckNoMatches`, `deckRelaxFilters`,
`deckSeenEveryone`, `deckRefresh`, `deckLoadFailed`, `deckRetry` — English values
from the strings listed in the spec, plus translations in all 12 siblings. Then
`flutter gen-l10n`.

- [ ] **Step 4: Persist gender and interests**

In `lib/providers/filter_provider.dart`, drop `onlineOnly` and `toggleOnlineOnly`,
and make the save write all four:

```dart
  /// Saves every filter. Gender is `lookingFor` on the profile, not a
  /// preference: the discovery query already reads that field, and a second
  /// field meaning the same thing would disagree with it.
  Future<bool> savePreferencesToApi() async {
    final prefs = await _userService.updatePreferences(
      minAge: state.minAge,
      maxAge: state.maxAge,
      maxDistance: state.maxDistance,
      interestsFilter: state.interests,
    );
    if (!prefs.success) return false;

    final gender = state.genderPreference;
    if (gender == null) return true;
    final profile = await _userService.updateProfile(lookingFor: gender);
    return profile.success;
  }
```

- [ ] **Step 5: Rebuild the sheet**

Age range and distance keep their sliders. The distance `Slider` takes
`onChanged: available ? (v) => ... : null` and renders
`context.l10n.filterDistanceNeedsLocation` beneath it when unavailable. Gender is
a segmented control over `Gender` plus `filterEveryone` for null. Interests is a
`Wrap` of `FilterChip`s built from `kInterests`, labelled
`interest.label(context.l10n)`, capped at 10 selections. The body is wrapped in
`ConstrainedBox(constraints: BoxConstraints(maxWidth: kSheetMaxWidth))` with
`key: const ValueKey('filters-body')`, centred on expanded windows.

On Apply: save, and only on success `ref.read(discoveryProvider.notifier).clearAndReload()`
then pop. On failure show `filterSaveFailed` and stay.

- [ ] **Step 6: Delete the dead flag**

Remove `advancedFiltersEnabled` from `lib/config/env.dart` (field, both presets,
the `testing` constructor) and from `test/config/env_flags_test.dart`. Of the
three filters it gated, two are now real and one was dropped.

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: analyze clean, tests PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/screens/discover/ lib/providers/filter_provider.dart lib/config/env.dart \
        lib/l10n/ test/screens/discover/ test/config/env_flags_test.dart
git commit -m "feat(discover): the filter sheet controls filters that exist

Age already worked. Distance now does. Gender writes lookingFor rather than a
second field that would disagree with the one the query reads, so a user can
finally change who they see without re-registering. Interests are a multi-select
over the shared catalogue.

Without location permission the distance slider is DISABLED with a reason rather
than silently doing nothing — that was the original defect, and it must not
reappear in a new costume.

A failed save keeps the sheet open and does not touch the deck: it must not look
saved when it is not. A successful save clears the deck rather than merging,
because cards chosen under the old filters read as the new ones being broken.

advancedFiltersEnabled is deleted — of the three filters it gated, two are real
now and one was dropped for being unable to explain itself: anyone who hid their
online status would have been excluded by an online-only filter with no way to
say so.

Sixteen strings localised across thirteen locales; chips wrap and the body is
width-constrained, both pinned by test."
```

---

## Task 13: App — three deck states, and the swipe surface

**Files:**
- Create: `lib/screens/discover/widgets/deck_states.dart`
- Modify: `lib/screens/discover/discover_screen.dart`
- Test: `test/screens/discover/deck_states_test.dart` (create)

**Interfaces:**
- Consumes: Tasks 7, 9, 10, 12.
- Produces: `DeckEmptyForFilters({required VoidCallback onRelaxFilters})`, `DeckSeenEveryone({required VoidCallback onRefresh})`, `DeckError({required String error, required VoidCallback onRetry})`.

- [ ] **Step 1: Write the failing test**

Create `test/screens/discover/deck_states_test.dart`, asserting that with filters
active and an empty deck the screen shows `DeckEmptyForFilters` and tapping
**Relax filters** pushes `/discover/filters`; that with no filters active it shows
`DeckSeenEveryone`; that an `AsyncValue.error` shows `DeckError` and never either
empty state; and that the deck is at most `kDeckMaxWidth` wide on a 1024-wide
window and raises no exception at text scale 2.0.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/discover/deck_states_test.dart`
Expected: FAIL — the file does not exist and the screen has one shared empty state.

- [ ] **Step 3: Write the three states**

Create `lib/screens/discover/widgets/deck_states.dart` with the three stateless
widgets, each a centred `Column` using `context.secondaryText` and
`context.onSurface`, no fixed-height wrapper around any text, and the action as a
`FilledButton`.

- [ ] **Step 4: Branch on them in the deck**

```dart
    return discoveryState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => DeckError(error: e.toString(), onRetry: _retry),
      data: (users) {
        if (users.isEmpty) {
          // Which fact is true matters: one is actionable and one is not.
          return filtersActive
              ? DeckEmptyForFilters(onRelaxFilters: _openFilters)
              : DeckSeenEveryone(onRefresh: _retry);
        }
        return _deck(users);
      },
    );
```

`filtersActive` is true when the stored preferences differ from the defaults —
age other than 18–50, an `interestsFilter`, or a `lookingFor` other than `other`.

Wrap the swiper in
`Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kDeckMaxWidth), child: ...))`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/discover/ test/screens/discover/deck_states_test.dart
git commit -m "feat(discover): three deck states instead of one guess

'Check back later or adjust your filters' guessed at two different facts and
covered a third it should never have covered. An empty deck because your filters
match nobody is actionable — it offers Relax filters. An empty deck because you
have seen everyone is not. A failed fetch is neither, and must never render as
either.

The deck is also constrained to kDeckMaxWidth and centred; a full-bleed swipe
card on a tablet is absurd."
```

---

## Task 14: App — dark mode across the Discover surface

**Files:**
- Modify: `lib/screens/discover/discover_screen.dart`, `discover_filters_screen.dart`, `lib/widgets/profile_card.dart`
- Modify: `lib/theme/app_theme.dart` (swipe accents)
- Create: `test/theme/discover_theme_test.dart`
- Modify: `test/theme/app_tokens_test.dart`

**Interfaces:**
- Consumes: Task 11's file layout.
- Produces: `AppColors.swipeLike`, `AppColors.swipeNope`, `AppColors.swipeSuperLike`.

- [ ] **Step 1: Write the failing gate**

Create `test/theme/discover_theme_test.dart`, the same shape as
`test/theme/chat_theme_test.dart`, scanning `lib/screens/discover` and
`lib/widgets/profile_card.dart` with the wide banned-colour regex.

- [ ] **Step 2: Run it to see the offenders**

Run: `flutter test test/theme/discover_theme_test.dart`
Expected: FAIL, listing roughly 38 lines — `profile_card.dart` 18,
the deck 12, the sheet 8.

- [ ] **Step 3: Name the swipe accents**

In `lib/theme/app_theme.dart`, beside `readReceipt`:

```dart
  /// Swipe affordances. Fixed in both themes, like [readReceipt]: green means
  /// yes and red means no regardless of how dark the app is.
  static const Color swipeLike = Color(0xFF27AE60);
  static const Color swipeNope = Color(0xFFE74C3C);
  static const Color swipeSuperLike = Color(0xFF2196F3);
```

- [ ] **Step 4: Sweep, and add the scrim**

Replace literals with tokens using the mapping already used for chat: surfaces →
`context.surface`, primary text → `context.onSurface`, secondary → `context.secondaryText`,
input and chip grounds → `context.fill`, hairlines → `context.divider`,
foreground on primary → `context.onPrimary`.

`profile_card.dart` needs more than substitution: its text sits **on a photo**, so
it uses `context.onOverlay` *and* gains a bottom-up gradient scrim behind the text
block:

```dart
        // A scrim, not decoration: white text over a bright photo is illegible
        // in either theme, and no token can fix that.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [
                  context.viewerScrim.withValues(alpha: 0.75),
                  context.viewerScrim.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
```

- [ ] **Step 5: Add the token-resolution assertions**

Append to `test/theme/app_tokens_test.dart` a test asserting, in both themes, that
`surfaceContainerHighest != surface`, `onSurfaceVariant != onSurface`,
`AppColors.swipeLike != AppColors.swipeNope`, and that `onOverlay` differs from
`viewerScrim` — because a scrim and the text on it being equal is exactly the
class of bug the literal gate cannot see.

- [ ] **Step 6: Run tests to verify they pass**

Run: `flutter analyze && flutter test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/discover/ lib/widgets/profile_card.dart lib/theme/ test/theme/
git commit -m "style(discover): the Discover surface honours the ColorScheme

38 colour literals become semantic tokens, and the gate now covers
lib/screens/discover and profile_card.

profile_card needed more than substitution: its text sits on a user photo, where
white is illegible over a bright image in either theme and no token can fix that.
It gets onOverlay plus a bottom-up gradient scrim — a legibility requirement, not
decoration.

The swipe accents are named constants rather than tokens pretending to vary:
green means yes and red means no however dark the app is.

Token-resolution assertions accompany the sweep, including that onOverlay differs
from viewerScrim. A scrim equal to the text on it is precisely what a
literal-banning lint cannot see."
```

---

## Task 15: Verify the whole surface

**Files:** none modified.

- [ ] **Step 1: App gate**

```bash
cd /Users/davis/Desktop/Personal/flame
flutter analyze
flutter test
```
Expected: 0 errors, 0 warnings; all tests pass. Record the count — it was 498
before this plan and must be higher.

- [ ] **Step 2: Backend gate**

```bash
cd /Users/davis/Desktop/Personal/language_exchange_backend_application
for f in flame/__tests__/*.test.js; do
  n=$(node --test "$f" 2>&1 | grep -E "^ℹ fail" | grep -oE "[0-9]+")
  [ "$n" != "0" ] && echo "FAILED: $f"
done
echo done
```
Expected: no `FAILED:` lines. Note that this suite has a pre-existing flake under
back-to-back runs; re-run any failure individually before treating it as real.

- [ ] **Step 3: Confirm the removals**

```bash
cd /Users/davis/Desktop/Personal/flame
grep -rn "advancedFiltersEnabled" lib/ test/ || echo "flag gone"
grep -rn "distanceText" lib/ || echo "old getter gone"
grep -rn "'offset'" lib/services/discovery_service.dart || echo "offset gone"
grep -rn "allInterests\|_InterestItem" lib/ || echo "duplicate catalogues gone"
test ! -d lib/screens/home && echo "home/ gone"
```
Expected: all five confirmations print.

- [ ] **Step 4: Walk it by hand**

```bash
flutter run --dart-define=APP_ENV=local
```

None of the above proves the surface looks right. Open Discover and confirm: a
real distance on the cards rather than "0 km away"; the filter sheet's distance
slider live with permission and disabled with a reason without it; gender and
interests changing the deck; the deck refilling as you swipe without repeating a
profile; dark mode legible over a bright photo; and the sheet readable at a large
system font size.

- [ ] **Step 5: Report**

State plainly what the walkthrough showed. If it found nothing, say so rather
than inventing a commit.

---

## Self-Review

**Spec coverage.** Distance filter → Task 2. Interests → Task 3. Gender → Task 12.
Refill contract → Tasks 4, 8, 9. Real distance honouring `showDistance` → Tasks 1,
6. `showDistance` asymmetry → Task 1's test. Location wiring → Task 10. Naming →
Task 11. Filter sheet → Task 12. Empty/error states → Task 13. Interest catalogue
and cross-repo tripwire → Tasks 3, 5. Localization → Tasks 5, 6, 12, 13.
Light/dark and the scrim → Task 14. Breakpoints, deck and sheet widths → Tasks 7,
12, 13. Text scaling → Tasks 12, 13. `max_distance` floor → Task 2. Every named
test has a task. Verification → Task 15.

**Two gaps found and closed while reviewing.** The spec says the deck refills when
fewer than three cards remain, but no task wired that trigger — it is now Task 9
Step 4. And `LocationResult.success` takes a `Position`, which cannot be
constructed in a unit test without a platform channel; Task 10 Step 3 adds
`LocationResult.successAt` for that, which the spec did not anticipate.

**One spec claim corrected.** The spec says `max_distance` "has no bounds today".
The mongoose schema has none, but the route's zod schema already validates
`min(0).max(500)`. The real change is the floor moving from 0 to 1, which Task 2
Step 4 states.

**Placeholder scan.** No TBDs. Two tasks give a mapping or an assertion list
rather than every literal edit — Task 14's colour sweep and Task 12's ARB keys —
which is the right altitude for mechanical work whose inputs are enumerated by a
failing test.

**Type consistency.** `DiscoveryResult({users, hasMore})` is defined in Task 8 and
consumed in Task 9. `refill()`, `load()`, `clearAndReload()` are named identically
in Tasks 9, 12, 13. `LocationAvailability` is produced in Task 10 and consumed in
Task 12. `kDeckMaxWidth` / `kSheetMaxWidth` are defined in Task 7 and used in
Tasks 12 and 13. `interestFor` / `kInterests` are defined in Task 5 and used in
Task 12. `haversineKm` is exported in Task 1 and tested there only.
