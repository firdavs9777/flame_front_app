# Profile Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the three profile features that already exist in the app but reach no server, stop leaking online status when a user has hidden it, and make profile and settings render correctly in both themes.

**Architecture:** Two new routes under `flame/routes/users.js` writing fields the `User` model already has. Online-status enforcement goes in `toDiscoverUser` — which `toConversation` already delegates to — plus the socket presence fan-out. App side: delete a dead service method, rework edit-profile into independently-saving sections, and replace hardcoded colours with `ColorScheme` tokens.

**Tech Stack:** Node/Express, Mongoose on Flame's own `getConn()` connection, `zod`. App: Flutter/Riverpod, Material 3. Tests: `node:test` + `mongodb-memory-server`; `flutter test`.

**Spec:** `docs/superpowers/specs/2026-08-17-profile-upgrade-design.md`

## Global Constraints

- **Two repos.** Backend: `~/Projects/BananaTalk/backend` (paths relative to it unless marked **APP**). App: `~/Desktop/Flame/flame_front_app` (marked **APP**).
- **Backend: only touch files under `flame/`.** BananaTalk's root code serves live users.
- Flame models end with `module.exports = getConn().model('Name', schema);` — never `mongoose.model()`.
- User ids are `String`. `auth` sets `req.user = { id: payload.userId }`. Response envelope is `{ success: true, data: {...} }`; errors from `flame/utils/errors.js` (`ValidationError` → 422, `NotFoundError` → 404, `ForbiddenError` → 403). Anything that is not a `FlameError` reaches the generic handler as a **500**.
- **Request bodies are fixed by the shipped app** — snake_case, per the contracts in each task. Renaming one breaks an installed client silently, because `user_service.dart` falls through to null rather than erroring.
- Backend tests: `node --test flame/__tests__/<file>` — **run in the FOREGROUND, one file at a time.** Never background a test run; never run the whole suite while iterating (~4 minutes, and it has hung agents).
- **Standing test corrections** — all four have bitten in this codebase:
  1. Fixture user names ≥2 characters (`User.name` has `minlength: 2`).
  2. Set `FLAME_SPACES_BUCKET`, `SPACES_ENDPOINT`, `DO_SPACES_KEY`, `DO_SPACES_SECRET` **before** any `require` — `flame/utils/s3.js` reads them at module load.
  3. Clear every required service from the require-cache array, **including `matchService` and `Match`** for anything touching chat, and **`blockService`** for anything touching blocks.
  4. **`setup(t)` must register `t.after(...)` immediately after `dbHelper.start()`**, before anything that can throw. Registering it at the end turned a correct RED run into a five-minute hang.
- The `User` model uses **sub-schemas**: `preferences` (`minAge`, `maxAge`, `maxDistance`, `showDistance`, `showOnlineStatus`), `notificationSettings`, `settings`, `location`, `locationGeo`. Fields are `user.preferences.minAge`, **not** `user.minAge`.
- `userService.MUTABLE_FIELDS` already allows `preferences`, `notificationSettings`, `settings`, `location`, `locationGeo` — so `updateMe` can already write them. Only routes are missing.
- App baselines: `flutter test` all passing, `flutter analyze` **0 errors and 0 warnings**.
- **Known flake:** a full-suite backend run fails roughly one test per run, a different one each time, on `main` too. Individual files pass. Re-run the single file to confirm before treating it as real.

---

## File Structure

**Backend (all under `flame/`)**

| File | Responsibility |
|---|---|
| `services/userService.js` (modify) | `updatePreferences`, `updateLocation` |
| `controllers/userController.js` (modify) | Map snake_case bodies to the service |
| `routes/users.js` (modify) | Mount both routes **before** `/:id` |
| `services/discoveryService.js` (modify) | Honour `showOnlineStatus` in `toDiscoverUser` |
| `socket/flameSocket.js` (modify) | Honour `showOnlineStatus` in the presence fan-out |

**App (all under `lib/`)**

| File | Responsibility |
|---|---|
| `services/user_service.dart` (modify) | Delete the dead `updateNotificationSettings` |
| `theme/app_tokens.dart` (new) | Semantic colour helpers over `ColorScheme` |
| `screens/profile/edit_profile_screen.dart` (modify) | Sectioned, independently-saving form |
| `screens/profile/my_profile_screen.dart` (modify) | Header, premium/verified state, tokens |
| `screens/settings/*.dart` (modify) | Tokens |

---

### Task 1: Preferences route

**Files:**
- Modify: `flame/services/userService.js`, `flame/controllers/userController.js`, `flame/routes/users.js`
- Test: `flame/__tests__/userPreferences.test.js`

**Interfaces:**
- Produces: `userService.updatePreferences(userId, patch)` → the updated `preferences` sub-document, where `patch` uses **camelCase** keys (`minAge`, `maxAge`, `maxDistance`, `showDistance`, `showOnlineStatus`); route `PATCH /users/me/preferences`

**Contract, fixed by the shipped app** (`APP lib/services/user_service.dart:94-111`):

```
PATCH /flamebackend/v1/users/me/preferences
body: { min_age?, max_age?, max_distance?, show_distance?, show_online_status? }
resp: { success: true, data: { preferences: { minAge, maxAge, maxDistance,
                                             showDistance, showOnlineStatus } } }
```

Every field optional — the app sends only what changed. `user_service.dart` reads `data['preferences']`.

**Sub-document, not top-level.** `preferences` is a Mongoose sub-schema (`flame/models/User.js:99`), so a partial update must use dotted paths (`preferences.minAge`) or it replaces the whole sub-document and resets the fields the caller did not send.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/userPreferences.test.js`:

```js
// Stub Flame's S3 util so tests don't hit DigitalOcean.
require.cache[require.resolve('../utils/s3')] = {
  exports: {
    uploadBuffer: async (_buf, key) => `https://stub.example.com/${key}`,
    deleteObject: async () => {},
    bucket: 'stub-bucket',
  },
};

const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const dbHelper = require('./helpers/db');

// Takes the test context so teardown registers BEFORE anything that can throw:
// a failing require in between leaves the mongod running and node never exits.
async function setup(t) {
  await dbHelper.start();
  t.after(async () => {
    try { await require('../db').close(); } catch { /* never opened */ }
    await dbHelper.stop();
  });

  process.env.FLAME_JWT_SECRET = 'a'.repeat(32);
  process.env.FLAME_JWT_REFRESH_SECRET = 'b'.repeat(32);
  process.env.FLAME_JWT_ACCESS_TTL = '5m';
  process.env.FLAME_JWT_REFRESH_TTL = '7d';
  process.env.FLAME_SPACES_BUCKET = 't';
  process.env.SPACES_ENDPOINT = 'e';
  process.env.DO_SPACES_KEY = 'k';
  process.env.DO_SPACES_SECRET = 's';

  [
    '../db', '../models/User', '../models/RefreshToken',
    '../services/authService', '../services/userService',
    '../services/visibilityService',
    '../controllers/authController', '../controllers/userController',
    '../routes/auth', '../routes/users', '../index',
  ].forEach((p) => { try { delete require.cache[require.resolve(p)]; } catch {} });

  const { connect } = require('../db');
  await connect();
  const { buildApp } = require('./helpers/app');
  return buildApp();
}

async function registerUser(app, email) {
  const body = {
    // padEnd guards against a short local-part, which would fail the auth
    // route's `name: z.string().min(2)` validation.
    email, password: 'Hunter2!!', name: email.split('@')[0].padEnd(2, 'x'),
    age: 25, gender: 'female', lookingFor: 'male', interests: ['x'],
  };
  const r = await request(app).post('/flamebackend/v1/auth/register').send(body).expect(201);
  return { token: r.body.data.tokens.accessToken, id: r.body.data.user.id };
}

const authH = (token) => ({ Authorization: `Bearer ${token}` });
const URL = '/flamebackend/v1/users/me/preferences';

test('updates every preference field', async (t) => {
  const app = await setup(t);
  const a = await registerUser(app, 'aa@x.com');

  const res = await request(app).patch(URL).set(authH(a.token))
    .send({
      min_age: 21, max_age: 35, max_distance: 25,
      show_distance: false, show_online_status: false,
    })
    .expect(200);

  const p = res.body.data.preferences;
  assert.equal(p.minAge, 21);
  assert.equal(p.maxAge, 35);
  assert.equal(p.maxDistance, 25);
  assert.equal(p.showDistance, false);
  assert.equal(p.showOnlineStatus, false);
});

test('a partial body leaves the other fields alone', async (t) => {
  const app = await setup(t);
  const a = await registerUser(app, 'bb@x.com');

  await request(app).patch(URL).set(authH(a.token))
    .send({ min_age: 21, max_age: 35 }).expect(200);

  // preferences is a Mongoose SUB-DOCUMENT. Writing it wholesale rather than by
  // dotted path would reset maxDistance and both privacy flags to their
  // defaults — silently turning privacy back on.
  const res = await request(app).patch(URL).set(authH(a.token))
    .send({ show_online_status: false }).expect(200);

  const p = res.body.data.preferences;
  assert.equal(p.showOnlineStatus, false);
  assert.equal(p.minAge, 21, 'an earlier update must survive a later partial one');
  assert.equal(p.maxAge, 35);
  assert.equal(p.maxDistance, 50, 'untouched fields keep their default');
});

test('the change persists', async (t) => {
  const app = await setup(t);
  const a = await registerUser(app, 'cc@x.com');

  await request(app).patch(URL).set(authH(a.token))
    .send({ min_age: 30 }).expect(200);

  const me = await request(app).get('/flamebackend/v1/users/me')
    .set(authH(a.token)).expect(200);

  assert.equal(me.body.data.preferences.minAge, 30);
});

test('an empty body is rejected rather than a no-op 200', async (t) => {
  const app = await setup(t);
  const a = await registerUser(app, 'dd@x.com');

  // A request that changes nothing is a client bug; answering 200 hides it.
  await request(app).patch(URL).set(authH(a.token)).send({}).expect(422);
});

test('out-of-range values are rejected', async (t) => {
  const app = await setup(t);
  const a = await registerUser(app, 'ee@x.com');

  // 18 is the floor everywhere else in this codebase; a dating app cannot
  // accept a preference below it.
  await request(app).patch(URL).set(authH(a.token))
    .send({ min_age: 17 }).expect(422);
  await request(app).patch(URL).set(authH(a.token))
    .send({ max_age: 200 }).expect(422);
  await request(app).patch(URL).set(authH(a.token))
    .send({ max_distance: -5 }).expect(422);
});

test('min_age above max_age is rejected', async (t) => {
  const app = await setup(t);
  const a = await registerUser(app, 'ff@x.com');

  // An inverted range matches nobody, and Discover would silently return an
  // empty feed that looks like "no one is near you".
  await request(app).patch(URL).set(authH(a.token))
    .send({ min_age: 40, max_age: 30 }).expect(422);
});

test('an unauthenticated request is rejected', async (t) => {
  const app = await setup(t);
  await request(app).patch(URL).send({ min_age: 21 }).expect(401);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Projects/BananaTalk/backend && node --test flame/__tests__/userPreferences.test.js`
Expected: FAIL — 404, route not mounted

- [ ] **Step 3: Add the service method**

In `flame/services/userService.js`, beside `updateMe`:

```js
const PREFERENCE_FIELDS = new Set([
  'minAge', 'maxAge', 'maxDistance', 'showDistance', 'showOnlineStatus',
]);

/**
 * Updates the caller's discovery preferences.
 *
 * `preferences` is a Mongoose sub-document, so this writes DOTTED paths
 * (`preferences.minAge`). Assigning the object wholesale would replace the
 * sub-document and reset every field the caller did not send — silently turning
 * the privacy flags back on, which is the worst possible direction for that
 * mistake.
 */
async function updatePreferences(userId, patch) {
  const update = {};
  for (const [k, v] of Object.entries(patch)) {
    if (PREFERENCE_FIELDS.has(k) && v !== undefined) update[`preferences.${k}`] = v;
  }
  if (Object.keys(update).length === 0) {
    throw new ValidationError('no preference fields to update');
  }

  const user = await User.findByIdAndUpdate(
    userId,
    { $set: update },
    { new: true, runValidators: true },
  );
  if (!user || user.isDeleted) throw new NotFoundError('User not found');
  return user.preferences;
}
```

Export `updatePreferences`.

- [ ] **Step 4: Add the controller**

In `flame/controllers/userController.js`:

```js
async function updatePreferences(req, res) {
  const b = req.body;
  const preferences = await userService.updatePreferences(req.user.id, {
    // snake_case in, camelCase out — the wire shape is fixed by the shipped app.
    minAge: b.min_age,
    maxAge: b.max_age,
    maxDistance: b.max_distance,
    showDistance: b.show_distance,
    showOnlineStatus: b.show_online_status,
  });
  res.json({ success: true, data: { preferences } });
}
```

Export it.

- [ ] **Step 5: Mount the route**

In `flame/routes/users.js`, **above** the `/:id` route, beside `/me/photos`:

```js
const preferencesSchema = z
  .object({
    min_age: z.number().int().min(18).max(100).optional(),
    max_age: z.number().int().min(18).max(100).optional(),
    max_distance: z.number().min(0).max(500).optional(),
    show_distance: z.boolean().optional(),
    show_online_status: z.boolean().optional(),
  })
  .refine((b) => Object.keys(b).length > 0, {
    message: 'at least one preference field is required',
  })
  .refine((b) => !(b.min_age && b.max_age) || b.min_age <= b.max_age, {
    message: 'min_age must not exceed max_age',
  });

router.patch('/me/preferences', auth, validate.body(preferencesSchema),
  asyncHandler(ctrl.updatePreferences));
```

- [ ] **Step 6: Run test to verify it passes**

Run: `node --test flame/__tests__/userPreferences.test.js`
Expected: PASS — 7 tests

- [ ] **Step 7: Confirm nothing regressed**

Run: `node --test flame/__tests__/users.test.js`
Expected: PASS — you added a route to a shared router.

- [ ] **Step 8: Commit**

```bash
git add flame/services/userService.js flame/controllers/userController.js \
        flame/routes/users.js flame/__tests__/userPreferences.test.js
git commit -m "feat(flame): add the preferences route the shipped app already calls"
```

---

### Task 2: Location route

**Files:**
- Modify: `flame/services/userService.js`, `flame/controllers/userController.js`, `flame/routes/users.js`
- Test: `flame/__tests__/userLocation.test.js`

**Interfaces:**
- Produces: `userService.updateLocation(userId, { latitude, longitude })` → the updated `location` sub-document; route `PATCH /users/me/location`

**Contract, fixed by the shipped app** (`APP lib/services/user_service.dart:80-92`):

```
PATCH /flamebackend/v1/users/me/location
body: { latitude, longitude }        // both required
resp: { success: true, data: { location: {...} } }
```

**The part that matters:** this must write **both** `location` and `locationGeo`. Discover queries the 2dsphere index on `locationGeo` (`flame/models/User.js:138`). Writing only `location` stores the coordinates and leaves Discover ranking on the old ones — which reads as "distance filtering is broken", not "location did not save".

`locationGeo.coordinates` is **`[longitude, latitude]`** — GeoJSON order, the reverse of how people say it. Getting it backwards puts users in the wrong hemisphere and produces plausible-looking wrong distances.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/userLocation.test.js`. Copy the `setup(t)` and `registerUser` helpers from Task 1's test verbatim — same require-cache list, same four standing corrections — then:

```js
const URL = '/flamebackend/v1/users/me/location';

test('stores the coordinates', async (t) => {
  const app = await setup(t);
  const a = await registerUser(app, 'aa@x.com');

  const res = await request(app).patch(URL).set(authH(a.token))
    .send({ latitude: 37.5665, longitude: 126.9780 })
    .expect(200);

  assert.equal(res.body.data.location.latitude, 37.5665);
  assert.equal(res.body.data.location.longitude, 126.9780);
});

test('writes locationGeo in GeoJSON order, longitude first', async (t) => {
  const app = await setup(t);
  const a = await registerUser(app, 'bb@x.com');

  await request(app).patch(URL).set(authH(a.token))
    .send({ latitude: 37.5665, longitude: 126.9780 }).expect(200);

  const User = require('../models/User');
  const user = await User.findById(a.id).lean();

  // GeoJSON is [lng, lat] — the reverse of how people say it. Swapping them
  // puts the user in the wrong hemisphere and yields plausible wrong distances.
  assert.deepEqual(user.locationGeo.coordinates, [126.9780, 37.5665]);
  assert.equal(user.locationGeo.type, 'Point');
});

test('a 2dsphere query finds the NEW position, not the old one', async (t) => {
  const app = await setup(t);
  const a = await registerUser(app, 'cc@x.com');
  const User = require('../models/User');
  await User.createIndexes();

  await request(app).patch(URL).set(authH(a.token))
    .send({ latitude: 37.5665, longitude: 126.9780 }).expect(200);
  await request(app).patch(URL).set(authH(a.token))
    .send({ latitude: 48.8566, longitude: 2.3522 }).expect(200);

  // The assertion that proves locationGeo is actually updated rather than
  // written once: search near Paris and find them, search near Seoul and not.
  const nearParis = await User.find({
    locationGeo: {
      $near: {
        $geometry: { type: 'Point', coordinates: [2.3522, 48.8566] },
        $maxDistance: 50000,
      },
    },
  }).lean();
  assert.equal(nearParis.length, 1);

  const nearSeoul = await User.find({
    locationGeo: {
      $near: {
        $geometry: { type: 'Point', coordinates: [126.9780, 37.5665] },
        $maxDistance: 50000,
      },
    },
  }).lean();
  assert.equal(nearSeoul.length, 0, 'the old position must not still match');
});

test('both coordinates are required', async (t) => {
  const app = await setup(t);
  const a = await registerUser(app, 'dd@x.com');

  await request(app).patch(URL).set(authH(a.token))
    .send({ latitude: 37.5 }).expect(422);
  await request(app).patch(URL).set(authH(a.token))
    .send({ longitude: 126.9 }).expect(422);
});

test('out-of-range coordinates are rejected', async (t) => {
  const app = await setup(t);
  const a = await registerUser(app, 'ee@x.com');

  // Mongo rejects these at query time with an opaque error; catching them here
  // gives the client something it can act on.
  await request(app).patch(URL).set(authH(a.token))
    .send({ latitude: 91, longitude: 0 }).expect(422);
  await request(app).patch(URL).set(authH(a.token))
    .send({ latitude: 0, longitude: 181 }).expect(422);
});

test('an unauthenticated request is rejected', async (t) => {
  const app = await setup(t);
  await request(app).patch(URL).send({ latitude: 0, longitude: 0 }).expect(401);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/userLocation.test.js`
Expected: FAIL — 404, route not mounted

- [ ] **Step 3: Add the service method**

In `flame/services/userService.js`:

```js
/**
 * Updates the caller's location.
 *
 * Writes BOTH `location` (human-readable, what the profile shows) and
 * `locationGeo` (the 2dsphere-indexed GeoJSON point Discover queries). Writing
 * only the first stores the coordinates and leaves Discover ranking on the old
 * position, which presents as broken distance filtering rather than a failed
 * save.
 */
async function updateLocation(userId, { latitude, longitude }) {
  const user = await User.findByIdAndUpdate(
    userId,
    {
      $set: {
        'location.latitude': latitude,
        'location.longitude': longitude,
        locationGeo: {
          type: 'Point',
          // GeoJSON is [longitude, latitude]. Reversed, this is a different
          // continent.
          coordinates: [longitude, latitude],
        },
      },
    },
    { new: true, runValidators: true },
  );
  if (!user || user.isDeleted) throw new NotFoundError('User not found');
  return user.location;
}
```

Export `updateLocation`.

- [ ] **Step 4: Add the controller**

In `flame/controllers/userController.js`:

```js
async function updateLocation(req, res) {
  const location = await userService.updateLocation(req.user.id, {
    latitude: req.body.latitude,
    longitude: req.body.longitude,
  });
  res.json({ success: true, data: { location } });
}
```

Export it.

- [ ] **Step 5: Mount the route**

In `flame/routes/users.js`, above `/:id`:

```js
const locationSchema = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
});

router.patch('/me/location', auth, validate.body(locationSchema),
  asyncHandler(ctrl.updateLocation));
```

- [ ] **Step 6: Run test to verify it passes**

Run: `node --test flame/__tests__/userLocation.test.js`
Expected: PASS — 6 tests

- [ ] **Step 7: Confirm nothing regressed**

Run: `node --test flame/__tests__/users.test.js`
Then: `node --test flame/__tests__/discoveryExclusion.test.js`
Expected: both pass — you touched a field Discover queries.

- [ ] **Step 8: Commit**

```bash
git add flame/services/userService.js flame/controllers/userController.js \
        flame/routes/users.js flame/__tests__/userLocation.test.js
git commit -m "feat(flame): add the location route, writing locationGeo alongside it"
```

---

### Task 3: Stop leaking online status

**Files:**
- Modify: `flame/services/discoveryService.js:5-25`
- Modify: `flame/socket/flameSocket.js`
- Test: `flame/__tests__/onlineStatusPrivacy.test.js`

**Interfaces:**
- Consumes: `preferences.showOnlineStatus` (Task 1 makes it settable)
- Produces: no new exports — behaviour only

**This is the task that closes a real leak.** `toDiscoverUser` returns `is_online: u.isOnline` unconditionally (`discoveryService.js:20`), and the presence fan-out broadcasts regardless. A user who turns online status off is still visible as online everywhere.

**One consolidation worth knowing:** `chatService.toConversation` builds its other-user block by calling `toDiscoverUser`, so fixing it there fixes the conversation list too. Do **not** add a second check in `toConversation` — one place answers the question, every caller asks it. That is the `visibilityService` pattern this codebase already uses for blocks.

**Do not touch `showDistance`.** `toDiscoverUser` hardcodes `distance: 0` and the file says why: *"No distance filtering yet — most users lack `locationGeo`."* There is no distance to hide, so a guard there would be dead code. The spec covers this.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/onlineStatusPrivacy.test.js`. Use Task 1's `setup(t)` helper, adding `'../services/discoveryService'`, `'../services/chatService'`, `'../services/matchService'`, `'../models/Match'`, `'../models/Conversation'`, `'../models/Message'`, `'../models/Swipe'`, `'../services/blockService'`, `'../routes/discovery'`, `'../routes/conversations'` to the require-cache list. Assert:

```js
// 1. A user with preferences.showOnlineStatus = false and isOnline = true
//    appears in GET /discover with is_online === false.
// 2. The same user with showOnlineStatus = true appears with is_online === true,
//    so the guard is conditional rather than a blanket false.
// 3. In GET /conversations, the other participant with showOnlineStatus = false
//    reads as is_online === false. Asserted SEPARATELY from Discover: one shared
//    helper passing does not prove a second call site uses it.
// 4. Hiding your own status does not hide theirs from you — the asymmetry is
//    deliberate, so a test pins it rather than leaving it to be "fixed" later.
```

Each of the first three is its own `test(...)`, not three assertions in one, so a failure names the leaking surface.

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/onlineStatusPrivacy.test.js`
Expected: FAIL — `is_online` is true despite the preference

- [ ] **Step 3: Honour the preference in the discovery shape**

In `flame/services/discoveryService.js`, in `toDiscoverUser`:

```js
    // A user who has hidden their online status reads as offline everywhere the
    // server describes them. chatService.toConversation delegates to this
    // function, so the conversation list is covered by the same line — one
    // place answers the question, every caller asks it, the way
    // visibilityService works for blocks.
    is_online: (u.preferences && u.preferences.showOnlineStatus === false)
      ? false
      : u.isOnline,
```

- [ ] **Step 4: Honour it in the presence fan-out**

Read `flame/socket/flameSocket.js` and find where `presence` is emitted and where the `presence:bulk` snapshot is assembled. Both must skip a user whose `preferences.showOnlineStatus` is false.

Load the flag from the user document rather than trusting anything the socket
carries — a client must not be able to assert its own visibility. Follow the
pattern `emitToReceiver` already uses: resolve state server-side and **fail
closed**, so a lookup failure hides the status rather than revealing it.

Say in your report which functions you changed and how you read the flag.

- [ ] **Step 5: Run test to verify it passes**

Run: `node --test flame/__tests__/onlineStatusPrivacy.test.js`
Expected: PASS

- [ ] **Step 6: Confirm presence still works for everyone else**

Run: `node --test flame/__tests__/presence.test.js`
Then: `node --test flame/__tests__/conversations.test.js`
Then: `node --test flame/__tests__/discoveryExclusion.test.js`
Expected: all pass. A blanket `false` would break `presence.test.js` — if it does, the guard is unconditional.

- [ ] **Step 7: Commit**

```bash
git add flame/services/discoveryService.js flame/socket/flameSocket.js \
        flame/__tests__/onlineStatusPrivacy.test.js
git commit -m "fix(flame): honour showOnlineStatus everywhere the server reports presence"
```

---

### Task 4: Delete the dead notification method

**Files:**
- Modify: `APP lib/services/user_service.dart:113-140`
- Test: `APP test/services/user_service_notifications_test.dart`

**Interfaces:**
- Produces: nothing — a removal

`user_service.updateNotificationSettings` posts to `/users/me/notifications`, which has no route. The working path is `PUT /notifications/settings`, already used by `notification_settings_screen.dart` through `NotificationService`. Two callers for one feature, one of them a 404.

Deleting the broken one is the fix. Adding a route to match it would leave two paths free to drift — the shape that produced the pin response, mute contract and refresh-token bugs in this codebase.

**No unit test for this one, deliberately.** Dart cannot assert at runtime that
a method does not exist, and a test that merely constructs `UserService` and
checks nothing would assert nothing — worse than no test. The analyzer is the
correct tool: it fails the build if anything references a deleted method. Steps 1
and 3 below are the check.

- [ ] **Step 1: Prove there is exactly one caller to remove**

Run:

```bash
cd ~/Desktop/Flame/flame_front_app
grep -rn "updateNotificationSettings" lib test
```

Expected: `lib/services/user_service.dart`, and whatever calls it. If a screen calls it, that screen must move to `NotificationService` **in this task** — leaving it calling a deleted method does not compile, and leaving it calling the 404 defeats the point. Report what you found.

- [ ] **Step 2: Delete the method**

Remove `updateNotificationSettings` from `APP lib/services/user_service.dart` entirely. If it was the only user of an import, remove that too.

- [ ] **Step 3: Prove nothing references it**

Run:

```bash
grep -rn "updateNotificationSettings" lib test ; echo "exit=$?"
flutter analyze
```

Expected: no matches, and 0 errors / 0 warnings. The analyzer is the check here — a runtime test cannot assert the absence of a method.

- [ ] **Step 4: Run the app suite**

Run: `flutter test`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/services/user_service.dart
git commit -m "fix(profile): delete the notification-settings method that always 404'd"
```

---

### Task 5: Theme tokens for profile and settings

**Files:**
- Create: `APP lib/theme/app_tokens.dart`
- Modify: every file under `APP lib/screens/profile/` and `APP lib/screens/settings/`
- Test: `APP test/theme/profile_settings_theme_test.dart`

**Interfaces:**
- Produces: `AppTokens` — an extension on `BuildContext` exposing `surface`, `onSurface`, `secondaryText`, `fill`, `divider`, `onPrimary`

`MaterialApp` already has `darkTheme` and `themeMode`, and `AppTheme` has real `ColorScheme.light` and `ColorScheme.dark` under Material 3 (`app_theme.dart:355,482`). Dark mode is **configured and then ignored** by 45 hardcoded colours in these two directories.

Brand colours stay literal: `AppTheme.primaryColor` is the brand in both themes and is not a theme-varying token.

- [ ] **Step 1: Write the failing test**

Create `APP test/theme/profile_settings_theme_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Dark mode was configured and then overridden. This is a lint-like test rather
// than a golden: goldens on themed screens break on every palette change and
// get regenerated without being read, which makes them worse than nothing.
void main() {
  test('profile and settings use theme tokens, not hardcoded colours', () {
    final offenders = <String>[];
    // Colors.transparent and Colors.red are intentional: one is not a colour,
    // and destructive actions are red in both themes by convention.
    final banned = RegExp(
      r'Colors\.(white|black|grey|black87|white70|white60|white54)',
    );

    for (final dir in ['lib/screens/profile', 'lib/screens/settings']) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (banned.hasMatch(lines[i])) {
            offenders.add('${entity.path}:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'these ignore the ColorScheme, so dark mode renders them wrong:\n'
          '${offenders.join('\n')}',
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme/profile_settings_theme_test.dart`
Expected: FAIL, listing roughly 45 offending lines with file and line number.

- [ ] **Step 3: Add the tokens**

Create `APP lib/theme/app_tokens.dart`:

```dart
import 'package:flutter/material.dart';

/// Semantic colours, resolved from the active [ColorScheme].
///
/// Exists because 349 hardcoded `Colors.*` literals across the app override a
/// perfectly good light/dark theme. Reaching for `context.secondaryText` is
/// shorter than `Theme.of(context).colorScheme.onSurfaceVariant`, which is the
/// only reason the literals won in the first place.
///
/// Brand colours are NOT here: `AppTheme.primaryColor` is the brand in both
/// themes and does not vary with it.
extension AppTokens on BuildContext {
  ColorScheme get _scheme => Theme.of(this).colorScheme;

  /// Page and card backgrounds.
  Color get surface => _scheme.surface;

  /// Body text and icons on [surface].
  Color get onSurface => _scheme.onSurface;

  /// Captions, hints, timestamps — present but not the point.
  Color get secondaryText => _scheme.onSurfaceVariant;

  /// Input fills and inset panels.
  Color get fill => _scheme.surfaceContainerHighest;

  /// Hairlines between rows.
  Color get divider => Theme.of(this).dividerColor;

  /// Text and icons sitting ON a primary-coloured surface — a filled button,
  /// a selected chip. Not the same as [surface]'s foreground.
  Color get onPrimary => _scheme.onPrimary;
}
```

- [ ] **Step 4: Replace the literals**

Work through the failures the test lists. The mapping:

| Hardcoded | Replacement |
|---|---|
| `Colors.white` as a background | `context.surface` |
| `Colors.black87`, `Colors.black` as text | `context.onSurface` |
| `Colors.grey[600]`, `[500]`, `[400]` as text | `context.secondaryText` |
| `Colors.grey[200]`, `[100]` as a fill | `context.fill` |
| `Colors.grey[300]` as a divider | `context.divider` |
| `Colors.white` **on** a primary-coloured surface | `context.onPrimary` |

Add `import 'package:flame/theme/app_tokens.dart';` to each file you touch.

A `StatelessWidget` build method has a `context`. A helper method that does not
take one needs `BuildContext context` added as a parameter — do that rather than
capturing a context in a field.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/theme/profile_settings_theme_test.dart`
Expected: PASS

- [ ] **Step 6: Check both themes render**

Run: `flutter test && flutter analyze`
Expected: all pass, 0 errors and 0 warnings.

- [ ] **Step 7: Commit**

```bash
git add lib/theme/app_tokens.dart lib/screens/profile lib/screens/settings \
        test/theme/profile_settings_theme_test.dart
git commit -m "feat(theme): profile and settings honour the ColorScheme"
```

---

### Task 6: Edit profile, sectioned

**Files:**
- Modify: `APP lib/screens/profile/edit_profile_screen.dart`
- Test: `APP test/screens/profile/edit_profile_test.dart`

**Interfaces:**
- Consumes: `UserService.updatePreferences` (Task 1's route), `AppTokens` (Task 5)
- Produces: no new exports

One long form becomes sectioned cards — Photos, About, Interests, Preferences — each saving independently, with validation **before** the request rather than a snackbar after it. Preferences appear here as editable controls for the first time, since Task 1 gave them a route.

- [ ] **Step 1: Write the failing test**

Create `APP test/screens/profile/edit_profile_test.dart` asserting:

```dart
// 1. An age below 18 is rejected BEFORE any request is made — assert the
//    injected save callback was never called, not merely that an error showed.
// 2. A name shorter than 2 characters is rejected before any request
//    (User.name has minlength: 2 server-side; failing here saves a round trip
//    and a confusing 422).
// 3. Saving the About section sends ONLY name, age and bio — not preferences.
//    Independent sections that quietly submit everything are not independent.
// 4. A failed save keeps the user's edits on screen rather than reverting them.
// 5. Setting min age above max age is rejected before any request, matching the
//    route's own refine.
```

Inject the save callbacks as parameters, the way `ChatSearchScreen` takes
`search`, so the screen is drivable without a network.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/profile/edit_profile_test.dart`
Expected: FAIL — the screen takes no injected callbacks yet

- [ ] **Step 3: Rework the screen**

Split the form into `_Section` cards, each with its own Save. Validate in the
handler and return early before calling the service. Wire the Preferences
section to `UserService.updatePreferences`.

**The Preferences section renders min age, max age, max distance and "Show
online status" — and NOT "Show distance".** `showDistance` is stored and
saveable, but `discoveryService.toDiscoverUser` hardcodes `distance: 0`, so a
toggle governing it would control a number always reported as zero. That is the
dead-button pattern the last two projects spent effort removing. It becomes real
in the change that makes distance real. The spec records this decision.

Keep the existing `AppTheme.primaryColor` usage — Task 5 covers colours, and
this task must not also churn them.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/profile/edit_profile_test.dart`
Expected: PASS — 5 tests

- [ ] **Step 5: Run the app suite**

Run: `flutter test && flutter analyze`
Expected: all pass, 0 errors and 0 warnings.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/profile/edit_profile_screen.dart \
        test/screens/profile/edit_profile_test.dart
git commit -m "feat(profile): sectioned edit form that validates before saving"
```

---

### Task 7: Profile header and premium state

**Files:**
- Modify: `APP lib/screens/profile/my_profile_screen.dart`
- Test: `APP test/screens/profile/my_profile_test.dart`

**Interfaces:**
- Consumes: `AppTokens` (Task 5), `BillingService` / `/billing/status`
- Produces: no new exports

`isVerified`, `isPremium` and `premiumExpiresAt` are parsed by `User` and shown
nowhere. `/billing/status` exists and is already called by `BillingService`, and
no screen displays the result.

- [ ] **Step 1: Write the failing test**

Create `APP test/screens/profile/my_profile_test.dart` asserting:

```dart
// 1. A verified user shows a verification badge; an unverified one shows none.
// 2. A premium user shows premium state; a non-premium one shows none —
//    NOT a greyed-out badge, which reads as "verification pending".
// 3. A premium user whose premiumExpiresAt is in the past does NOT show as
//    premium. An expired subscription rendering as active is the one failure
//    that costs money to get wrong.
```

Build the screen with an overridden user provider, following
`test/providers/conversations_realtime_test.dart`'s `_Seeded` pattern.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/profile/my_profile_test.dart`
Expected: FAIL — no badge is rendered

- [ ] **Step 3: Add the header**

Render the verification badge and premium state. Treat premium as active only
when `isPremium` is true **and** `premiumExpiresAt` is null or in the future.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/profile/my_profile_test.dart`
Expected: PASS — 3 tests

- [ ] **Step 5: Run the app suite**

Run: `flutter test && flutter analyze`
Expected: all pass, 0 errors and 0 warnings.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/profile/my_profile_screen.dart \
        test/screens/profile/my_profile_test.dart
git commit -m "feat(profile): show verification and premium state"
```

---

### Task 8: End-to-end verification

**Files:** none — a manual gate.

- [ ] **Step 1: Full backend suite**

```bash
cd ~/Projects/BananaTalk/backend
node --test --test-concurrency=1 flame/__tests__/
```

Expected: everything passes except possibly ONE test — the known flake, a
different one each run, present on `main` too. Re-run that single file before
treating it as real.

- [ ] **Step 2: Full app suite**

```bash
cd ~/Desktop/Flame/flame_front_app
flutter test && flutter analyze
```

Expected: all pass, 0 errors and 0 warnings.

- [ ] **Step 3: No legacy-index check needed**

This project adds no collection and no index. `PATCH /me/location` writes an
already-indexed field. Recorded so nobody spends time looking for a gate that
does not apply here.

- [ ] **Step 4: Verify by hand**

1. Edit Profile → change the age range and distance → reopen the app. The values
   persist. Before this they silently did not.
2. Settings → turn off "Show online status". On a second device, that user reads
   as **offline** in Discover and in the Messages list.
3. Turn it back on → they read as online again, proving the guard is conditional.
4. Switch the app to dark mode. Profile and settings are legible throughout.
   **Chat will still look wrong** — its 104 hardcoded colours are deliberately
   out of scope, per the spec.
5. Toggle notification settings. They still save, through
   `PUT /notifications/settings`, which was always the working path.
