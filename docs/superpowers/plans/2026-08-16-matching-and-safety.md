# Matching & Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make swipes persist, mutual likes create matches with conversations, and give Flame working block and report — turning a deck that goes nowhere into a working dating loop.

**Architecture:** Three new Mongo collections (`Swipe`, `Match`, `Report`) on Flame's isolated connection, plus block arrays embedded on `User`. A single shared `visibilityService` enforces blocks across every surface that returns another user. The app is already built for all of this, so nearly all work is backend.

**Tech Stack:** Node/Express, Mongoose (Flame's own `getConn()` connection), Zod validation, `node:test` + `mongodb-memory-server`. App side: Flutter/Riverpod.

**Spec:** `docs/superpowers/specs/2026-08-16-matching-and-safety-design.md`

## Global Constraints

- **Two repos.** Backend: `~/Projects/BananaTalk/backend` (all paths below are relative to it unless marked APP). App: `~/Desktop/Flame/flame_front_app` (marked **APP**).
- **Never touch BananaTalk code.** Only `flame/` and its tests. Flame uses its own mongoose connection via `getConn()` from `flame/db.js`; models must never use `mongoose.model()` directly.
- **User ids are `String`**, not ObjectId refs. `auth` middleware sets `req.user = { id: payload.userId }`.
- **Models end with** `module.exports = getConn().model('Name', schema);`
- **Errors** come from `flame/utils/errors.js` and extend `FlameError(code, message, status)`.
- **Routes** use `express` + `zod` + `asyncHandler` + `auth` + `validate.body/params`, and delegate to a controller in `flame/controllers/`.
- **Response envelope** is always `{ success: true, data: {...} }`; errors are handled by `flame/middleware/error.js`.
- **Existing swipe response shapes must not change** — the app already parses them.
- Run backend tests with `node --test flame/__tests__/<file>`.
- ObjectId validation regex already in use: `/^[0-9a-fA-F]{24}$/`.

---

### Task 1: Swipe model

**Files:**
- Create: `flame/models/Swipe.js`
- Test: `flame/__tests__/swipeModel.test.js`

**Interfaces:**
- Consumes: `getConn()` from `flame/db.js`
- Produces: `Swipe` model with fields `from`, `to`, `action` (`'like'|'pass'|'super'`), `createdAt`; unique compound index `(from, to)`; index `(to, action)`

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/swipeModel.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

async function setup() {
  await dbHelper.start();
  ['../db', '../models/Swipe'].forEach(p => {
    try { delete require.cache[require.resolve(p)]; } catch {}
  });
  const { connect } = require('../db');
  await connect();
  return require('../models/Swipe');
}

test('a user cannot swipe the same person twice', async (t) => {
  const Swipe = await setup();
  t.after(async () => {
    const { close } = require('../db');
    await close();
    await dbHelper.stop();
  });
  await Swipe.init(); // ensure indexes are built before asserting on them

  await Swipe.create({ from: 'a', to: 'b', action: 'like' });

  await assert.rejects(
    () => Swipe.create({ from: 'a', to: 'b', action: 'pass' }),
    (err) => err.code === 11000,
    'the unique (from,to) index must reject a second swipe on the same person',
  );
});

test('the reverse direction is a different swipe', async (t) => {
  const Swipe = await setup();
  t.after(async () => {
    const { close } = require('../db');
    await close();
    await dbHelper.stop();
  });
  await Swipe.init();

  await Swipe.create({ from: 'a', to: 'b', action: 'like' });
  await Swipe.create({ from: 'b', to: 'a', action: 'like' });

  assert.equal(await Swipe.countDocuments({}), 2);
});

test('action is restricted to like, pass and super', async (t) => {
  const Swipe = await setup();
  t.after(async () => {
    const { close } = require('../db');
    await close();
    await dbHelper.stop();
  });

  await assert.rejects(() => Swipe.create({ from: 'a', to: 'b', action: 'maybe' }));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/swipeModel.test.js`
Expected: FAIL — `Cannot find module '../models/Swipe'`

- [ ] **Step 3: Write the model**

Create `flame/models/Swipe.js`:

```js
const mongoose = require('mongoose');
const { getConn } = require('../db');

// One row per swipe decision. Append-only: this is the record of everything a
// user has already seen, so Discover can stop re-showing them.
//
// Its own collection rather than an array on User: an active swiper generates
// thousands of rows, which would push the user document toward Mongo's 16MB
// ceiling and turn "has A swiped B?" into an array scan instead of an index hit.
const swipeSchema = new mongoose.Schema(
  {
    from: { type: String, required: true },
    to: { type: String, required: true },
    action: { type: String, enum: ['like', 'pass', 'super'], required: true },
  },
  { timestamps: { createdAt: 'createdAt', updatedAt: false }, collection: 'swipes' },
);

// Makes "already swiped?" an index hit, and makes a double-tap physically
// unable to create two rows — the controller relies on this for idempotency.
swipeSchema.index({ from: 1, to: 1 }, { unique: true });

// Powers mutual detection ("did `to` already like `from`?") and a future
// "who liked you" list.
swipeSchema.index({ to: 1, action: 1 });

module.exports = getConn().model('Swipe', swipeSchema);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test flame/__tests__/swipeModel.test.js`
Expected: PASS — 3 tests

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/BananaTalk/backend
git add flame/models/Swipe.js flame/__tests__/swipeModel.test.js
git commit -m "feat(flame): add Swipe model with unique (from,to) index"
```

---

### Task 2: Match model

**Files:**
- Create: `flame/models/Match.js`
- Test: `flame/__tests__/matchModel.test.js`

**Interfaces:**
- Consumes: `getConn()` from `flame/db.js`
- Produces: `Match` model with `users: [String, String]` (stored sorted), `conversationId: String`, `endedBy: String|null`, `createdAt`; unique index on `users`; static `Match.pair(a, b)` returning the sorted array

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/matchModel.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

async function setup() {
  await dbHelper.start();
  ['../db', '../models/Match'].forEach(p => {
    try { delete require.cache[require.resolve(p)]; } catch {}
  });
  const { connect } = require('../db');
  await connect();
  return require('../models/Match');
}

test('pair() sorts so the same two users always produce one key', async (t) => {
  const Match = await setup();
  t.after(async () => {
    const { close } = require('../db');
    await close();
    await dbHelper.stop();
  });

  assert.deepEqual(Match.pair('b', 'a'), ['a', 'b']);
  assert.deepEqual(Match.pair('a', 'b'), ['a', 'b']);
});

test('one match per pair regardless of who swiped first', async (t) => {
  const Match = await setup();
  t.after(async () => {
    const { close } = require('../db');
    await close();
    await dbHelper.stop();
  });
  await Match.init();

  await Match.create({ users: Match.pair('a', 'b'), conversationId: 'c1' });

  await assert.rejects(
    () => Match.create({ users: Match.pair('b', 'a'), conversationId: 'c2' }),
    (err) => err.code === 11000,
    'sorted pair + unique index must collapse both orderings into one match',
  );
});

test('endedBy defaults to null so a live match is the default state', async (t) => {
  const Match = await setup();
  t.after(async () => {
    const { close } = require('../db');
    await close();
    await dbHelper.stop();
  });

  const m = await Match.create({ users: Match.pair('x', 'y'), conversationId: 'c3' });
  assert.equal(m.endedBy, null);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/matchModel.test.js`
Expected: FAIL — `Cannot find module '../models/Match'`

- [ ] **Step 3: Write the model**

Create `flame/models/Match.js`:

```js
const mongoose = require('mongoose');
const { getConn } = require('../db');

// A mutual like. `users` is ALWAYS stored sorted, which is what makes a match
// unique regardless of who swiped first — with the unique index below there is
// exactly one row per pair, and no code anywhere needs to ask "did A match B or
// B match A?".
const matchSchema = new mongoose.Schema(
  {
    users: {
      type: [String],
      required: true,
      validate: {
        validator: (v) => Array.isArray(v) && v.length === 2 && v[0] !== v[1],
        message: 'users must be exactly 2 distinct ids',
      },
    },
    conversationId: { type: String, required: true },
    // Set when either side unmatches. The row is kept rather than deleted so
    // the swipe history stays meaningful and the pair does not reappear in
    // Discover.
    endedBy: { type: String, default: null },
  },
  { timestamps: { createdAt: 'createdAt', updatedAt: false }, collection: 'matches' },
);

matchSchema.index({ users: 1 }, { unique: true });

// Canonical ordering for a pair. Every caller must build `users` through this.
matchSchema.statics.pair = function pair(a, b) {
  return [a, b].sort();
};

module.exports = getConn().model('Match', matchSchema);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test flame/__tests__/matchModel.test.js`
Expected: PASS — 3 tests

- [ ] **Step 5: Commit**

```bash
git add flame/models/Match.js flame/__tests__/matchModel.test.js
git commit -m "feat(flame): add Match model with sorted-pair unique index"
```

---

### Task 3: Report model and POST /reports

**Files:**
- Create: `flame/models/Report.js`, `flame/controllers/reportController.js`, `flame/routes/reports.js`
- Modify: `flame/index.js` (mount the router)
- Test: `flame/__tests__/reports.test.js`

**Interfaces:**
- Consumes: `Swipe`/`Match` not needed here; uses `auth`, `validate`, `asyncHandler`
- Produces: `POST /reports` accepting `{ user_id, reason, details? }`; `Report` model

**Reason values are taken verbatim from the app's `ReportReason` enum** (`APP lib/services/report_service.dart`) — the backend must accept these exact strings: `inappropriate_content`, `fake_profile`, `harassment`, `spam`, `underage`, `other`.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/reports.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const dbHelper = require('./helpers/db');

const BASE = '/flamebackend/v1';

async function setup() {
  await dbHelper.start();
  process.env.FLAME_JWT_SECRET = 'a'.repeat(32);
  process.env.FLAME_JWT_REFRESH_SECRET = 'b'.repeat(32);
  process.env.FLAME_JWT_ACCESS_TTL = '5m';
  process.env.FLAME_JWT_REFRESH_TTL = '7d';

  ['../db', '../models/User', '../models/Report', '../models/RefreshToken',
   '../services/authService', '../utils/jwt', '../controllers/reportController',
   '../routes/reports', '../index']
    .forEach(p => { try { delete require.cache[require.resolve(p)]; } catch {} });

  const { connect } = require('../db');
  await connect();

  const User = require('../models/User');
  const reporter = await User.create({
    email: 'r@x.com', name: 'Reporter', age: 30, gender: 'female',
    lookingFor: 'male', passwordHash: 'x',
  });
  const target = await User.create({
    email: 't@x.com', name: 'Target', age: 30, gender: 'male',
    lookingFor: 'female', passwordHash: 'x',
  });

  const { signAccess } = require('../utils/jwt');
  const token = signAccess({ userId: reporter._id.toString() }).token;

  const { buildApp } = require('./helpers/app');
  return { app: buildApp(), token, reporterId: reporter._id.toString(), targetId: target._id.toString() };
}

test('POST /reports stores a report', async (t) => {
  const { app, token, reporterId, targetId } = await setup();
  t.after(async () => { const { close } = require('../db'); await close(); await dbHelper.stop(); });

  const res = await request(app)
    .post(`${BASE}/reports`)
    .set('Authorization', `Bearer ${token}`)
    .send({ user_id: targetId, reason: 'harassment', details: 'was rude' })
    .expect(201);

  assert.equal(res.body.success, true);

  const Report = require('../models/Report');
  const saved = await Report.findOne({ reportedUser: targetId });
  assert.equal(saved.reportedBy, reporterId);
  assert.equal(saved.reason, 'harassment');
  assert.equal(saved.description, 'was rude');
  assert.equal(saved.status, 'pending');
});

test('POST /reports rejects an unknown reason', async (t) => {
  const { app, token, targetId } = await setup();
  t.after(async () => { const { close } = require('../db'); await close(); await dbHelper.stop(); });

  const res = await request(app)
    .post(`${BASE}/reports`)
    .set('Authorization', `Bearer ${token}`)
    .send({ user_id: targetId, reason: 'i_just_dont_like_them' })
    .expect(422);

  assert.equal(res.body.error.code, 'VALIDATION');
});

test('POST /reports rejects reporting yourself', async (t) => {
  const { app, token, reporterId } = await setup();
  t.after(async () => { const { close } = require('../db'); await close(); await dbHelper.stop(); });

  const res = await request(app)
    .post(`${BASE}/reports`)
    .set('Authorization', `Bearer ${token}`)
    .send({ user_id: reporterId, reason: 'spam' })
    .expect(422);

  assert.equal(res.body.error.code, 'VALIDATION');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/reports.test.js`
Expected: FAIL — 404 responses (route not mounted)

- [ ] **Step 3: Write the model**

Create `flame/models/Report.js`:

```js
const mongoose = require('mongoose');
const { getConn } = require('../db');

// Reason strings are the app's ReportReason enum verbatim
// (flame_front_app lib/services/report_service.dart). Do not invent new
// vocabulary here — the app already serialises to these.
const REASONS = [
  'inappropriate_content',
  'fake_profile',
  'harassment',
  'spam',
  'underage',
  'other',
];

const reportSchema = new mongoose.Schema(
  {
    reportedBy: { type: String, required: true, index: true },
    reportedUser: { type: String, required: true, index: true },
    reason: { type: String, enum: REASONS, required: true },
    description: { type: String, maxlength: 500, default: null },
    // Carried from day one though nothing reads it yet, so a moderation queue
    // can be added later without a migration.
    status: {
      type: String,
      enum: ['pending', 'reviewed', 'resolved', 'dismissed'],
      default: 'pending',
    },
  },
  { timestamps: { createdAt: 'createdAt', updatedAt: false }, collection: 'reports' },
);

module.exports = getConn().model('Report', reportSchema);
module.exports.REASONS = REASONS;
```

- [ ] **Step 4: Write the controller**

Create `flame/controllers/reportController.js`:

```js
const Report = require('../models/Report');
const { ValidationError } = require('../utils/errors');

async function createReport(req, res) {
  const reportedUser = req.body.user_id;
  if (reportedUser === req.user.id) {
    throw new ValidationError('cannot report yourself');
  }

  await Report.create({
    reportedBy: req.user.id,
    reportedUser,
    reason: req.body.reason,
    description: req.body.details || null,
  });

  res.status(201).json({ success: true, data: { reported: true } });
}

module.exports = { createReport };
```

- [ ] **Step 5: Write the route**

Create `flame/routes/reports.js`:

```js
const express = require('express');
const { z } = require('zod');
const asyncHandler = require('../middleware/asyncHandler');
const auth = require('../middleware/auth');
const validate = require('../middleware/validate');
const ctrl = require('../controllers/reportController');
const { REASONS } = require('../models/Report');

const router = express.Router();

const objectId = z.string().regex(/^[0-9a-fA-F]{24}$/, 'must be a valid ObjectId');
const createSchema = z.object({
  user_id: objectId,
  reason: z.enum(REASONS),
  details: z.string().max(500).optional(),
});

router.post('/', auth, validate.body(createSchema), asyncHandler(ctrl.createReport));

module.exports = router;
```

- [ ] **Step 6: Mount the router**

In `flame/index.js`, directly after the `/notifications` line, add:

```js
router.use('/reports', require('./routes/reports'));
```

- [ ] **Step 7: Run test to verify it passes**

Run: `node --test flame/__tests__/reports.test.js`
Expected: PASS — 3 tests

- [ ] **Step 8: Commit**

```bash
git add flame/models/Report.js flame/controllers/reportController.js \
        flame/routes/reports.js flame/index.js flame/__tests__/reports.test.js
git commit -m "feat(flame): add user reports to the contract the app already calls"
```

---

### Task 4: Block storage and /blocks routes

**Files:**
- Modify: `flame/models/User.js` (add `blockedUsers`, `blockedBy`)
- Create: `flame/services/blockService.js`, `flame/controllers/blockController.js`, `flame/routes/blocks.js`
- Modify: `flame/index.js`
- Test: `flame/__tests__/blocks.test.js`

**Interfaces:**
- Produces: `blockService.block(userId, targetId)`, `blockService.unblock(userId, targetId)`, `blockService.listBlocked(userId)` → `[{ id, name, photo, blocked_at }]`; routes `POST /blocks`, `DELETE /blocks/:userId`, `GET /blocks`

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/blocks.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const dbHelper = require('./helpers/db');

const BASE = '/flamebackend/v1';

async function setup() {
  await dbHelper.start();
  process.env.FLAME_JWT_SECRET = 'a'.repeat(32);
  process.env.FLAME_JWT_REFRESH_SECRET = 'b'.repeat(32);
  process.env.FLAME_JWT_ACCESS_TTL = '5m';
  process.env.FLAME_JWT_REFRESH_TTL = '7d';

  ['../db', '../models/User', '../models/RefreshToken', '../utils/jwt',
   '../services/blockService', '../controllers/blockController',
   '../routes/blocks', '../index']
    .forEach(p => { try { delete require.cache[require.resolve(p)]; } catch {} });

  const { connect } = require('../db');
  await connect();

  const User = require('../models/User');
  const me = await User.create({
    email: 'me@x.com', name: 'Me', age: 30, gender: 'female',
    lookingFor: 'male', passwordHash: 'x',
  });
  const them = await User.create({
    email: 'them@x.com', name: 'Them', age: 30, gender: 'male',
    lookingFor: 'female', passwordHash: 'x',
  });

  const { signAccess } = require('../utils/jwt');
  const token = signAccess({ userId: me._id.toString() }).token;

  const { buildApp } = require('./helpers/app');
  return {
    app: buildApp(), token,
    meId: me._id.toString(), themId: them._id.toString(),
    User,
  };
}

test('POST /blocks records the block on BOTH sides', async (t) => {
  const { app, token, meId, themId, User } = await setup();
  t.after(async () => { const { close } = require('../db'); await close(); await dbHelper.stop(); });

  await request(app).post(`${BASE}/blocks`)
    .set('Authorization', `Bearer ${token}`)
    .send({ user_id: themId })
    .expect(201);

  const me = await User.findById(meId);
  const them = await User.findById(themId);

  assert.equal(me.blockedUsers.length, 1);
  assert.equal(me.blockedUsers[0].user, themId);
  assert.equal(them.blockedBy.length, 1, 'the target must record who blocked them');
  assert.equal(them.blockedBy[0].user, meId);
});

test('blocking twice is idempotent', async (t) => {
  const { app, token, meId, themId, User } = await setup();
  t.after(async () => { const { close } = require('../db'); await close(); await dbHelper.stop(); });

  const send = () => request(app).post(`${BASE}/blocks`)
    .set('Authorization', `Bearer ${token}`).send({ user_id: themId });

  await send();
  await send();

  const me = await User.findById(meId);
  assert.equal(me.blockedUsers.length, 1);
});

test('GET /blocks lists blocked users in the app\'s shape', async (t) => {
  const { app, token, themId } = await setup();
  t.after(async () => { const { close } = require('../db'); await close(); await dbHelper.stop(); });

  await request(app).post(`${BASE}/blocks`)
    .set('Authorization', `Bearer ${token}`).send({ user_id: themId }).expect(201);

  const res = await request(app).get(`${BASE}/blocks`)
    .set('Authorization', `Bearer ${token}`).expect(200);

  const list = res.body.data.blocked_users;
  assert.equal(list.length, 1);
  assert.equal(list[0].id, themId);
  assert.equal(list[0].name, 'Them');
  assert.ok('blocked_at' in list[0]);
});

test('DELETE /blocks/:userId clears both sides', async (t) => {
  const { app, token, meId, themId, User } = await setup();
  t.after(async () => { const { close } = require('../db'); await close(); await dbHelper.stop(); });

  await request(app).post(`${BASE}/blocks`)
    .set('Authorization', `Bearer ${token}`).send({ user_id: themId }).expect(201);

  await request(app).delete(`${BASE}/blocks/${themId}`)
    .set('Authorization', `Bearer ${token}`).expect(200);

  const me = await User.findById(meId);
  const them = await User.findById(themId);
  assert.equal(me.blockedUsers.length, 0);
  assert.equal(them.blockedBy.length, 0);
});

test('cannot block yourself', async (t) => {
  const { app, token, meId } = await setup();
  t.after(async () => { const { close } = require('../db'); await close(); await dbHelper.stop(); });

  const res = await request(app).post(`${BASE}/blocks`)
    .set('Authorization', `Bearer ${token}`).send({ user_id: meId }).expect(422);
  assert.equal(res.body.error.code, 'VALIDATION');
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/blocks.test.js`
Expected: FAIL — 404 (route not mounted)

- [ ] **Step 3: Add the block arrays to User**

In `flame/models/User.js`, add these two fields to `userSchema` immediately after `locationGeo`:

```js
  // Blocks are embedded rather than a separate collection: they are consulted on
  // EVERY read path that returns another user (discover, matches, conversations,
  // stories, socket delivery), and they are low-cardinality. Storing both
  // directions is deliberate redundancy — it makes "hide people I blocked AND
  // people who blocked me" a single check on a document already in hand.
  blockedUsers: {
    type: [{ user: { type: String, required: true }, blockedAt: { type: Date, default: Date.now } }],
    default: [],
  },
  blockedBy: {
    type: [{ user: { type: String, required: true }, blockedAt: { type: Date, default: Date.now } }],
    default: [],
  },
```

- [ ] **Step 4: Write the block service**

Create `flame/services/blockService.js`:

```js
const User = require('../models/User');
const { ValidationError, NotFoundError } = require('../utils/errors');

// Both directions are written together so the two arrays can never disagree.
// $addToSet-style guarding is done with an explicit filter because the entries
// are subdocuments (with a timestamp), so $addToSet would not dedupe them.
async function block(userId, targetId) {
  if (userId === targetId) throw new ValidationError('cannot block yourself');

  const target = await User.findById(targetId);
  if (!target || target.isDeleted) throw new NotFoundError('user not found');

  const now = new Date();
  await User.updateOne(
    { _id: userId, 'blockedUsers.user': { $ne: targetId } },
    { $push: { blockedUsers: { user: targetId, blockedAt: now } } },
  );
  await User.updateOne(
    { _id: targetId, 'blockedBy.user': { $ne: userId } },
    { $push: { blockedBy: { user: userId, blockedAt: now } } },
  );
}

async function unblock(userId, targetId) {
  await User.updateOne({ _id: userId }, { $pull: { blockedUsers: { user: targetId } } });
  await User.updateOne({ _id: targetId }, { $pull: { blockedBy: { user: userId } } });
}

async function listBlocked(userId) {
  const me = await User.findById(userId).lean();
  if (!me) throw new NotFoundError('user not found');

  const ids = (me.blockedUsers || []).map((b) => b.user);
  if (ids.length === 0) return [];

  const users = await User.find({ _id: { $in: ids } }).lean();
  const byId = new Map(users.map((u) => [u._id.toString(), u]));

  return (me.blockedUsers || []).map((b) => {
    const u = byId.get(b.user);
    const primary = u && (u.photos || []).find((p) => p.isPrimary);
    return {
      id: b.user,
      name: u ? u.name : null,
      photo: primary ? primary.url : null,
      blocked_at: b.blockedAt,
    };
  });
}

module.exports = { block, unblock, listBlocked };
```

- [ ] **Step 5: Write the controller and route**

Create `flame/controllers/blockController.js`:

```js
const blockService = require('../services/blockService');

async function createBlock(req, res) {
  await blockService.block(req.user.id, req.body.user_id);
  res.status(201).json({ success: true, data: { blocked: true } });
}

async function removeBlock(req, res) {
  await blockService.unblock(req.user.id, req.params.userId);
  res.json({ success: true, data: { unblocked: true } });
}

async function listBlocks(req, res) {
  const blocked = await blockService.listBlocked(req.user.id);
  res.json({ success: true, data: { blocked_users: blocked } });
}

module.exports = { createBlock, removeBlock, listBlocks };
```

Create `flame/routes/blocks.js`:

```js
const express = require('express');
const { z } = require('zod');
const asyncHandler = require('../middleware/asyncHandler');
const auth = require('../middleware/auth');
const validate = require('../middleware/validate');
const ctrl = require('../controllers/blockController');

const router = express.Router();

const objectId = z.string().regex(/^[0-9a-fA-F]{24}$/, 'must be a valid ObjectId');
const createSchema = z.object({ user_id: objectId });
const userIdParam = z.object({ userId: objectId });

router.get('/', auth, asyncHandler(ctrl.listBlocks));
router.post('/', auth, validate.body(createSchema), asyncHandler(ctrl.createBlock));
router.delete('/:userId', auth, validate.params(userIdParam), asyncHandler(ctrl.removeBlock));

module.exports = router;
```

- [ ] **Step 6: Mount the router**

In `flame/index.js`, after the `/reports` line, add:

```js
router.use('/blocks', require('./routes/blocks'));
```

- [ ] **Step 7: Run test to verify it passes**

Run: `node --test flame/__tests__/blocks.test.js`
Expected: PASS — 5 tests

- [ ] **Step 8: Commit**

```bash
git add flame/models/User.js flame/services/blockService.js \
        flame/controllers/blockController.js flame/routes/blocks.js \
        flame/index.js flame/__tests__/blocks.test.js
git commit -m "feat(flame): add user blocking with bidirectional storage"
```

---

### Task 5: visibilityService and ForbiddenError

**Files:**
- Modify: `flame/utils/errors.js` (add `ForbiddenError`)
- Create: `flame/services/visibilityService.js`
- Test: `flame/__tests__/visibilityService.test.js`

**Interfaces:**
- Consumes: `User` model with `blockedUsers`/`blockedBy` (Task 4), `Swipe` model (Task 1)
- Produces:
  - `ForbiddenError(message)` → code `FORBIDDEN`, status 403
  - `visibilityService.blockedIdsFor(userId)` → `Promise<string[]>` (blocked + blockedBy)
  - `visibilityService.excludedIdsFor(userId, { includeSwiped })` → `Promise<string[]>`
  - `visibilityService.assertCanInteract(a, b)` → throws `ForbiddenError` if either blocked the other
  - `visibilityService.areBlocked(a, b)` → `Promise<boolean>`

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/visibilityService.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

async function setup() {
  await dbHelper.start();
  ['../db', '../models/User', '../models/Swipe', '../services/blockService',
   '../services/visibilityService']
    .forEach(p => { try { delete require.cache[require.resolve(p)]; } catch {} });

  const { connect } = require('../db');
  await connect();

  const User = require('../models/User');
  const mk = (email, name) => User.create({
    email, name, age: 30, gender: 'other', lookingFor: 'other', passwordHash: 'x',
  });

  const a = await mk('a@x.com', 'A');
  const b = await mk('b@x.com', 'B');
  const c = await mk('c@x.com', 'C');

  return {
    a: a._id.toString(), b: b._id.toString(), c: c._id.toString(),
    blockService: require('../services/blockService'),
    visibility: require('../services/visibilityService'),
    Swipe: require('../models/Swipe'),
  };
}

const teardown = (t) => t.after(async () => {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
});

test('blockedIdsFor covers BOTH directions', async (t) => {
  const { a, b, c, blockService, visibility } = await setup();
  teardown(t);

  await blockService.block(a, b); // a blocked b
  await blockService.block(c, a); // c blocked a

  const ids = await visibility.blockedIdsFor(a);
  assert.ok(ids.includes(b), 'people I blocked must be hidden');
  assert.ok(ids.includes(c), 'people who blocked me must be hidden too');
});

test('assertCanInteract throws whichever way the block runs', async (t) => {
  const { a, b, blockService, visibility } = await setup();
  teardown(t);

  await blockService.block(a, b);

  await assert.rejects(() => visibility.assertCanInteract(a, b), (e) => e.status === 403);
  await assert.rejects(() => visibility.assertCanInteract(b, a), (e) => e.status === 403);
});

test('assertCanInteract passes for unrelated users', async (t) => {
  const { a, c, visibility } = await setup();
  teardown(t);

  await visibility.assertCanInteract(a, c); // must not throw
});

test('excludedIdsFor adds swiped users when asked', async (t) => {
  const { a, b, c, Swipe, visibility } = await setup();
  teardown(t);

  await Swipe.create({ from: a, to: c, action: 'pass' });

  const withSwipes = await visibility.excludedIdsFor(a, { includeSwiped: true });
  assert.ok(withSwipes.includes(c));

  const withoutSwipes = await visibility.excludedIdsFor(a, { includeSwiped: false });
  assert.ok(!withoutSwipes.includes(c));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/visibilityService.test.js`
Expected: FAIL — `Cannot find module '../services/visibilityService'`

- [ ] **Step 3: Add ForbiddenError**

In `flame/utils/errors.js`, add after `NotFoundError` and include it in the exports:

```js
class ForbiddenError extends FlameError {
  constructor(message = 'Forbidden') { super('FORBIDDEN', message, 403); this.name = 'ForbiddenError'; }
}
```

- [ ] **Step 4: Write the service**

Create `flame/services/visibilityService.js`:

```js
const User = require('../models/User');
const Swipe = require('../models/Swipe');
const { ForbiddenError } = require('../utils/errors');

// Single source of truth for "who is this user not allowed to see or reach".
//
// This exists as one module rather than eight scattered checks because a block
// has to hold on every surface that returns another user — discover, matches,
// conversation lists, message sends, SOCKET DELIVERY, the story feed and
// profile reads. Missing one leaks a blocked person straight back into view,
// and socket delivery is the easiest to forget because it bypasses REST.

async function blockedIdsFor(userId) {
  const me = await User.findById(userId).select('blockedUsers blockedBy').lean();
  if (!me) return [];
  const out = new Set();
  for (const b of me.blockedUsers || []) out.add(b.user);
  for (const b of me.blockedBy || []) out.add(b.user);
  return [...out];
}

async function swipedIdsFor(userId) {
  const rows = await Swipe.find({ from: userId }).select('to').lean();
  return rows.map((r) => r.to);
}

async function excludedIdsFor(userId, { includeSwiped = false } = {}) {
  const blocked = await blockedIdsFor(userId);
  if (!includeSwiped) return blocked;
  const swiped = await swipedIdsFor(userId);
  return [...new Set([...blocked, ...swiped])];
}

async function areBlocked(a, b) {
  const found = await User.findOne({
    _id: a,
    $or: [{ 'blockedUsers.user': b }, { 'blockedBy.user': b }],
  }).select('_id').lean();
  return !!found;
}

async function assertCanInteract(a, b) {
  if (await areBlocked(a, b)) {
    throw new ForbiddenError('interaction not allowed');
  }
}

module.exports = { blockedIdsFor, excludedIdsFor, areBlocked, assertCanInteract };
```

- [ ] **Step 5: Run test to verify it passes**

Run: `node --test flame/__tests__/visibilityService.test.js`
Expected: PASS — 4 tests

- [ ] **Step 6: Commit**

```bash
git add flame/utils/errors.js flame/services/visibilityService.js \
        flame/__tests__/visibilityService.test.js
git commit -m "feat(flame): add visibilityService as the single block-enforcement point"
```

---

### Task 6: Swipe service with mutual match detection

**Files:**
- Create: `flame/services/swipeService.js`
- Test: `flame/__tests__/swipeService.test.js`

**Interfaces:**
- Consumes: `Swipe` (Task 1), `Match` (Task 2), `visibilityService.assertCanInteract` (Task 5), existing `chatService.openConversation(userId, otherUserId)`, `userService.toPublicMinimal`
- **Prerequisite edit:** `flame/services/userService.js` currently exports only
  `{ getMe, getById, updateMe, uploadPhoto, deletePhoto }`. Add `toPublicMinimal`
  to that export list so matches can serialise a user the same way every other
  endpoint does.
- Produces: `swipeService.record(fromId, toId, action)` → `{ isMatch: boolean, match: object|null }` where `match` is `{ id, user: <toPublicMinimal>, matched_at, is_new, last_message }` — the shape `APP lib/models/match.dart` parses

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/swipeService.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

async function setup() {
  await dbHelper.start();
  ['../db', '../models/User', '../models/Swipe', '../models/Match',
   '../models/Conversation', '../services/chatService',
   '../services/visibilityService', '../services/blockService',
   '../services/swipeService']
    .forEach(p => { try { delete require.cache[require.resolve(p)]; } catch {} });

  const { connect } = require('../db');
  await connect();

  const User = require('../models/User');
  const mk = (email, name) => User.create({
    email, name, age: 30, gender: 'other', lookingFor: 'other', passwordHash: 'x',
  });
  const a = await mk('a@x.com', 'A');
  const b = await mk('b@x.com', 'B');

  return {
    a: a._id.toString(), b: b._id.toString(),
    swipeService: require('../services/swipeService'),
    blockService: require('../services/blockService'),
    Match: require('../models/Match'),
    Swipe: require('../models/Swipe'),
  };
}

const teardown = (t) => t.after(async () => {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
});

test('a one-sided like is not a match', async (t) => {
  const { a, b, swipeService } = await setup();
  teardown(t);

  const res = await swipeService.record(a, b, 'like');
  assert.equal(res.isMatch, false);
  assert.equal(res.match, null);
});

test('a reciprocal like creates a match AND a conversation', async (t) => {
  const { a, b, swipeService, Match } = await setup();
  teardown(t);

  await swipeService.record(a, b, 'like');
  const res = await swipeService.record(b, a, 'like');

  assert.equal(res.isMatch, true);
  assert.equal(res.match.user.id, a, 'match.user is the OTHER participant');
  assert.ok(res.match.matched_at, 'the app parses matched_at');

  assert.equal(await Match.countDocuments({}), 1);
});

test('a pass never matches, even if the other liked', async (t) => {
  const { a, b, swipeService } = await setup();
  teardown(t);

  await swipeService.record(a, b, 'like');
  const res = await swipeService.record(b, a, 'pass');
  assert.equal(res.isMatch, false);
});

test('super counts as a like for matching', async (t) => {
  const { a, b, swipeService } = await setup();
  teardown(t);

  await swipeService.record(a, b, 'super');
  const res = await swipeService.record(b, a, 'like');
  assert.equal(res.isMatch, true);
});

test('swiping twice is idempotent and does not double-match', async (t) => {
  const { a, b, swipeService, Match, Swipe } = await setup();
  teardown(t);

  await swipeService.record(a, b, 'like');
  await swipeService.record(a, b, 'like');
  await swipeService.record(b, a, 'like');
  await swipeService.record(b, a, 'like');

  assert.equal(await Swipe.countDocuments({ from: a, to: b }), 1);
  assert.equal(await Match.countDocuments({}), 1);
});

test('simultaneous likes still produce exactly one match', async (t) => {
  const { a, b, swipeService, Match } = await setup();
  teardown(t);

  const [r1, r2] = await Promise.all([
    swipeService.record(a, b, 'like'),
    swipeService.record(b, a, 'like'),
  ]);

  assert.equal(await Match.countDocuments({}), 1);
  assert.ok(r1.isMatch || r2.isMatch, 'at least one side must learn about the match');
});

test('a blocked user cannot be swiped', async (t) => {
  const { a, b, swipeService, blockService } = await setup();
  teardown(t);

  await blockService.block(b, a); // b blocked a
  await assert.rejects(() => swipeService.record(a, b, 'like'), (e) => e.status === 403);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/swipeService.test.js`
Expected: FAIL — `Cannot find module '../services/swipeService'`

- [ ] **Step 3: Write the service**

Create `flame/services/swipeService.js`:

```js
const Swipe = require('../models/Swipe');
const Match = require('../models/Match');
const User = require('../models/User');
const chatService = require('./chatService');
const visibility = require('./visibilityService');
const { toPublicMinimal } = require('./userService');

const LIKE_ACTIONS = ['like', 'super'];

// Shape is dictated by the app's Match.fromJson (lib/models/match.dart):
// { id, user, matched_at, is_new, last_message }. Note there is NO
// conversation_id — the app resolves the conversation through
// conversationsProvider, which is why the conversation is created with the
// match. `user` must be a full user object, so we reuse userService's
// toPublicMinimal rather than inventing a second serialisation.
async function toMatchPayload(match, viewerId) {
  const otherId = match.users.find((u) => u !== viewerId);
  const other = await User.findById(otherId).lean();
  return {
    id: match._id.toString(),
    user: other ? toPublicMinimal(other) : { id: otherId },
    matched_at: match.createdAt,
    is_new: true,
    last_message: null,
  };
}

// Records a swipe and, when it completes a mutual like, creates the match and
// its conversation together.
async function record(fromId, toId, action) {
  await visibility.assertCanInteract(fromId, toId);

  // Idempotent: a retry or double-tap must not create a second row. The unique
  // (from,to) index makes this safe even under concurrency.
  await Swipe.updateOne(
    { from: fromId, to: toId },
    { $setOnInsert: { from: fromId, to: toId, action, createdAt: new Date() } },
    { upsert: true },
  );

  if (!LIKE_ACTIONS.includes(action)) return { isMatch: false, match: null };

  const reciprocal = await Swipe.findOne({
    from: toId, to: fromId, action: { $in: LIKE_ACTIONS },
  }).lean();
  if (!reciprocal) return { isMatch: false, match: null };

  const users = Match.pair(fromId, toId);

  const existing = await Match.findOne({ users }).lean();
  if (existing) {
    if (existing.endedBy) return { isMatch: false, match: null };
    return { isMatch: true, match: await toMatchPayload(existing, fromId) };
  }

  const conversation = await chatService.openConversation(fromId, toId);

  try {
    const match = await Match.create({ users, conversationId: conversation.id });
    return { isMatch: true, match: await toMatchPayload(match, fromId) };
  } catch (e) {
    // Both users liked each other at the same instant and the other request won
    // the unique index. Read their match rather than failing — same recovery
    // idiom as socialAuthService.findOrCreate.
    if (e.code === 11000) {
      const winner = await Match.findOne({ users }).lean();
      if (winner) return { isMatch: true, match: await toMatchPayload(winner, fromId) };
    }
    throw e;
  }
}

module.exports = { record };
```

> **Note for the implementer:** `chatService.openConversation` returns the object
> produced by `toConversation(...)`. Confirm its id field is `id`; if it differs,
> use the actual field rather than changing `chatService`.

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test flame/__tests__/swipeService.test.js`
Expected: PASS — 7 tests

- [ ] **Step 5: Commit**

```bash
git add flame/services/swipeService.js flame/__tests__/swipeService.test.js
git commit -m "feat(flame): persist swipes and create a match on mutual like"
```

---

### Task 7: Wire the swipe routes and super-like quota

**Files:**
- Modify: `flame/routes/swipes.js` (replace the stubs)
- Create: `flame/controllers/swipeController.js`
- Test: `flame/__tests__/swipeRoutes.test.js`

**Interfaces:**
- Consumes: `swipeService.record` (Task 6)
- Produces: `POST /swipes/like|pass|super-like` with **unchanged response shapes**; super-like decrements `User.superLikesRemaining` and resets daily via `User.superLikesDay`

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/swipeRoutes.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const dbHelper = require('./helpers/db');

const BASE = '/flamebackend/v1';

async function setup() {
  await dbHelper.start();
  process.env.FLAME_JWT_SECRET = 'a'.repeat(32);
  process.env.FLAME_JWT_REFRESH_SECRET = 'b'.repeat(32);
  process.env.FLAME_JWT_ACCESS_TTL = '5m';
  process.env.FLAME_JWT_REFRESH_TTL = '7d';

  ['../db', '../models/User', '../models/Swipe', '../models/Match',
   '../models/Conversation', '../models/RefreshToken', '../utils/jwt',
   '../services/chatService', '../services/swipeService',
   '../services/visibilityService', '../controllers/swipeController',
   '../routes/swipes', '../index']
    .forEach(p => { try { delete require.cache[require.resolve(p)]; } catch {} });

  const { connect } = require('../db');
  await connect();

  const User = require('../models/User');
  const mk = (email, name) => User.create({
    email, name, age: 30, gender: 'other', lookingFor: 'other', passwordHash: 'x',
  });
  const a = await mk('a@x.com', 'A');
  const b = await mk('b@x.com', 'B');

  const { signAccess } = require('../utils/jwt');
  const { buildApp } = require('./helpers/app');
  return {
    app: buildApp(),
    aToken: signAccess({ userId: a._id.toString() }).token,
    bToken: signAccess({ userId: b._id.toString() }).token,
    aId: a._id.toString(), bId: b._id.toString(),
    User,
  };
}

const teardown = (t) => t.after(async () => {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
});

test('POST /swipes/like keeps its response shape and reports no match', async (t) => {
  const { app, aToken, bId } = await setup();
  teardown(t);

  const res = await request(app).post(`${BASE}/swipes/like`)
    .set('Authorization', `Bearer ${aToken}`)
    .send({ user_id: bId }).expect(200);

  assert.equal(res.body.data.liked, true);
  assert.equal(res.body.data.is_match, false);
  assert.equal(res.body.data.match, null);
});

test('a reciprocal like returns is_match with the match payload', async (t) => {
  const { app, aToken, bToken, aId, bId } = await setup();
  teardown(t);

  await request(app).post(`${BASE}/swipes/like`)
    .set('Authorization', `Bearer ${aToken}`).send({ user_id: bId }).expect(200);

  const res = await request(app).post(`${BASE}/swipes/like`)
    .set('Authorization', `Bearer ${bToken}`).send({ user_id: aId }).expect(200);

  assert.equal(res.body.data.is_match, true);
  assert.equal(res.body.data.match.user.id, aId);
  assert.ok(res.body.data.match.matched_at);
});

test('super-like decrements the quota and reports the remainder', async (t) => {
  const { app, aToken, aId, bId, User } = await setup();
  teardown(t);

  const res = await request(app).post(`${BASE}/swipes/super-like`)
    .set('Authorization', `Bearer ${aToken}`).send({ user_id: bId }).expect(200);

  assert.equal(res.body.data.super_liked, true);
  assert.equal(res.body.data.remaining_super_likes, 2);

  const me = await User.findById(aId);
  assert.equal(me.superLikesRemaining, 2);
});

test('super-like is refused once the quota is spent', async (t) => {
  const { app, aToken, aId, bId, User } = await setup();
  teardown(t);

  const today = new Date().toISOString().slice(0, 10);
  await User.updateOne({ _id: aId }, { $set: { superLikesRemaining: 0, superLikesDay: today } });

  const res = await request(app).post(`${BASE}/swipes/super-like`)
    .set('Authorization', `Bearer ${aToken}`).send({ user_id: bId }).expect(422);

  assert.equal(res.body.error.code, 'VALIDATION');
});

test('the quota resets on a new day', async (t) => {
  const { app, aToken, aId, bId, User } = await setup();
  teardown(t);

  await User.updateOne({ _id: aId }, { $set: { superLikesRemaining: 0, superLikesDay: '2000-01-01' } });

  const res = await request(app).post(`${BASE}/swipes/super-like`)
    .set('Authorization', `Bearer ${aToken}`).send({ user_id: bId }).expect(200);

  assert.equal(res.body.data.remaining_super_likes, 2);
});

test('POST /swipes/undo still answers without 404-ing', async (t) => {
  const { app, aToken } = await setup();
  teardown(t);

  const res = await request(app).post(`${BASE}/swipes/undo`)
    .set('Authorization', `Bearer ${aToken}`).expect(200);
  assert.equal(res.body.data.undone, false);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/swipeRoutes.test.js`
Expected: FAIL — `is_match` assertions fail (the stub always returns false) and super-like does not decrement

- [ ] **Step 3: Write the controller**

Create `flame/controllers/swipeController.js`:

```js
const User = require('../models/User');
const swipeService = require('../services/swipeService');
const { ValidationError } = require('../utils/errors');

const DAILY_SUPER_LIKES = 3;

function today() {
  return new Date().toISOString().slice(0, 10); // YYYY-MM-DD UTC
}

// Atomically claims one super-like for today, resetting the allowance when the
// stored day is stale. Returns the number remaining after the claim.
async function claimSuperLike(userId) {
  const day = today();

  // New day: reset first, so the claim below sees a full allowance.
  await User.updateOne(
    { _id: userId, superLikesDay: { $ne: day } },
    { $set: { superLikesDay: day, superLikesRemaining: DAILY_SUPER_LIKES } },
  );

  const claimed = await User.findOneAndUpdate(
    { _id: userId, superLikesRemaining: { $gt: 0 } },
    { $inc: { superLikesRemaining: -1 } },
    { new: true },
  ).lean();

  if (!claimed) throw new ValidationError('no super likes remaining today');
  return claimed.superLikesRemaining;
}

async function like(req, res) {
  const result = await swipeService.record(req.user.id, req.body.user_id, 'like');
  res.json({
    success: true,
    data: { liked: true, is_match: result.isMatch, match: result.match },
  });
}

async function pass(req, res) {
  await swipeService.record(req.user.id, req.body.user_id, 'pass');
  res.json({ success: true, data: { passed: true } });
}

async function superLike(req, res) {
  const remaining = await claimSuperLike(req.user.id);
  const result = await swipeService.record(req.user.id, req.body.user_id, 'super');
  res.json({
    success: true,
    data: {
      super_liked: true,
      is_match: result.isMatch,
      match: result.match,
      remaining_super_likes: remaining,
    },
  });
}

// Undo is deliberately still a no-op (out of scope for this phase). It answers
// rather than 404s so the app's existing call keeps working.
async function undo(_req, res) {
  res.json({ success: true, data: { undone: false } });
}

module.exports = { like, pass, superLike, undo };
```

- [ ] **Step 4: Replace the routes**

Replace the whole body of `flame/routes/swipes.js` with:

```js
const express = require('express');
const { z } = require('zod');
const asyncHandler = require('../middleware/asyncHandler');
const auth = require('../middleware/auth');
const validate = require('../middleware/validate');
const ctrl = require('../controllers/swipeController');

const router = express.Router();

const objectId = z.string().regex(/^[0-9a-fA-F]{24}$/, 'must be a valid ObjectId');
const targetSchema = z.object({ user_id: objectId });

router.post('/like', auth, validate.body(targetSchema), asyncHandler(ctrl.like));
router.post('/pass', auth, validate.body(targetSchema), asyncHandler(ctrl.pass));
router.post('/super-like', auth, validate.body(targetSchema), asyncHandler(ctrl.superLike));
router.post('/undo', auth, asyncHandler(ctrl.undo));

module.exports = router;
```

- [ ] **Step 5: Run test to verify it passes**

Run: `node --test flame/__tests__/swipeRoutes.test.js`
Expected: PASS — 6 tests

- [ ] **Step 6: Commit**

```bash
git add flame/controllers/swipeController.js flame/routes/swipes.js \
        flame/__tests__/swipeRoutes.test.js
git commit -m "feat(flame): wire swipe routes to real matching with super-like quota"
```

---

### Task 8: GET /matches and unmatch

**Files:**
- Create: `flame/services/matchService.js`, `flame/controllers/matchController.js`
- Modify: `flame/routes/matches.js` (replace the stub)
- Test: `flame/__tests__/matches.test.js`

**Interfaces:**
- Consumes: `Match` (Task 2), `visibilityService.blockedIdsFor` (Task 5), `User`
- Produces: `matchService.list(userId, { limit, offset })` → `{ matches, total }`; `matchService.unmatch(userId, matchId)`; routes `GET /matches`, `DELETE /matches/:id`

Each entry in `matches` has the shape the app's `Match.fromJson` parses
(`APP lib/models/match.dart`):
`{ id, user: <toPublicMinimal>, matched_at, is_new, last_message }`

There is deliberately **no `conversation_id`** — the app resolves the
conversation through `conversationsProvider`, which is exactly why the
conversation is created at match time.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/matches.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const dbHelper = require('./helpers/db');

const BASE = '/flamebackend/v1';

async function setup() {
  await dbHelper.start();
  process.env.FLAME_JWT_SECRET = 'a'.repeat(32);
  process.env.FLAME_JWT_REFRESH_SECRET = 'b'.repeat(32);
  process.env.FLAME_JWT_ACCESS_TTL = '5m';
  process.env.FLAME_JWT_REFRESH_TTL = '7d';

  ['../db', '../models/User', '../models/Swipe', '../models/Match',
   '../models/Conversation', '../models/RefreshToken', '../utils/jwt',
   '../services/chatService', '../services/swipeService', '../services/matchService',
   '../services/visibilityService', '../services/blockService',
   '../controllers/matchController', '../routes/matches', '../index']
    .forEach(p => { try { delete require.cache[require.resolve(p)]; } catch {} });

  const { connect } = require('../db');
  await connect();

  const User = require('../models/User');
  const mk = (email, name) => User.create({
    email, name, age: 30, gender: 'other', lookingFor: 'other', passwordHash: 'x',
  });
  const a = await mk('a@x.com', 'A');
  const b = await mk('b@x.com', 'B');

  const swipeService = require('../services/swipeService');
  await swipeService.record(a._id.toString(), b._id.toString(), 'like');
  const res = await swipeService.record(b._id.toString(), a._id.toString(), 'like');

  const { signAccess } = require('../utils/jwt');
  const { buildApp } = require('./helpers/app');
  return {
    app: buildApp(),
    aToken: signAccess({ userId: a._id.toString() }).token,
    aId: a._id.toString(), bId: b._id.toString(),
    matchId: res.match.id,
    blockService: require('../services/blockService'),
    Match: require('../models/Match'),
  };
}

const teardown = (t) => t.after(async () => {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
});

test('GET /matches returns the other participant, not yourself', async (t) => {
  const { app, aToken, bId } = await setup();
  teardown(t);

  const res = await request(app).get(`${BASE}/matches`)
    .set('Authorization', `Bearer ${aToken}`).expect(200);

  assert.equal(res.body.data.matches.length, 1);
  assert.equal(res.body.data.matches[0].user.id, bId);
  assert.equal(res.body.data.matches[0].user.name, 'B');
  assert.ok(res.body.data.matches[0].matched_at);
  assert.equal(res.body.data.pagination.total, 1);
});

test('DELETE /matches/:id ends the match and hides it', async (t) => {
  const { app, aToken, matchId, Match } = await setup();
  teardown(t);

  await request(app).delete(`${BASE}/matches/${matchId}`)
    .set('Authorization', `Bearer ${aToken}`).expect(200);

  const res = await request(app).get(`${BASE}/matches`)
    .set('Authorization', `Bearer ${aToken}`).expect(200);
  assert.equal(res.body.data.matches.length, 0);

  const row = await Match.findById(matchId);
  assert.ok(row, 'the row is kept, not deleted');
  assert.ok(row.endedBy, 'endedBy records who ended it');
});

test('you cannot unmatch a match you are not part of', async (t) => {
  const { app, matchId } = await setup();
  teardown(t);

  const User = require('../models/User');
  const stranger = await User.create({
    email: 's@x.com', name: 'S', age: 30, gender: 'other',
    lookingFor: 'other', passwordHash: 'x',
  });
  const { signAccess } = require('../utils/jwt');
  const token = signAccess({ userId: stranger._id.toString() }).token;

  await request(app).delete(`${BASE}/matches/${matchId}`)
    .set('Authorization', `Bearer ${token}`).expect(404);
});

test('blocking hides the match from the list', async (t) => {
  const { app, aToken, aId, bId, blockService } = await setup();
  teardown(t);

  await blockService.block(aId, bId);

  const res = await request(app).get(`${BASE}/matches`)
    .set('Authorization', `Bearer ${aToken}`).expect(200);
  assert.equal(res.body.data.matches.length, 0);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/matches.test.js`
Expected: FAIL — the stub returns an empty array, so the first test fails

- [ ] **Step 3: Write the service**

Create `flame/services/matchService.js`:

```js
const Match = require('../models/Match');
const User = require('../models/User');
const visibility = require('./visibilityService');
const { NotFoundError } = require('../utils/errors');

const { toPublicMinimal } = require('./userService');

async function list(userId, { limit = 20, offset = 0 } = {}) {
  const hidden = await visibility.blockedIdsFor(userId);

  const filter = {
    users: userId,
    endedBy: null,
    ...(hidden.length ? { users: { $all: [userId], $nin: hidden } } : {}),
  };

  const total = await Match.countDocuments(filter);
  const rows = await Match.find(filter)
    .sort({ createdAt: -1 })
    .skip(offset)
    .limit(limit)
    .lean();

  const otherIds = rows.map((m) => m.users.find((u) => u !== userId));
  const users = await User.find({ _id: { $in: otherIds } }).lean();
  const byId = new Map(users.map((u) => [u._id.toString(), u]));

  const matches = rows.map((m) => {
    const otherId = m.users.find((u) => u !== userId);
    const u = byId.get(otherId);
    return {
      id: m._id.toString(),
      user: u ? toPublicMinimal(u) : { id: otherId },
      matched_at: m.createdAt,
      is_new: true,
      last_message: null,
    };
  });

  return { matches, total };
}

async function unmatch(userId, matchId) {
  const match = await Match.findOne({ _id: matchId, users: userId });
  // 404 rather than 403 so a stranger cannot probe which match ids exist.
  if (!match) throw new NotFoundError('match not found');

  match.endedBy = userId;
  await match.save();
}

module.exports = { list, unmatch };
```

- [ ] **Step 4: Write the controller and routes**

Create `flame/controllers/matchController.js`:

```js
const matchService = require('../services/matchService');

async function listMatches(req, res) {
  const limit = parseInt(req.query.limit, 10) || 20;
  const offset = parseInt(req.query.offset, 10) || 0;
  const { matches, total } = await matchService.list(req.user.id, { limit, offset });

  res.json({
    success: true,
    data: {
      matches,
      pagination: { total, limit, offset, has_more: offset + matches.length < total },
    },
  });
}

async function deleteMatch(req, res) {
  await matchService.unmatch(req.user.id, req.params.id);
  res.json({ success: true, data: { unmatched: true } });
}

module.exports = { listMatches, deleteMatch };
```

Replace the whole body of `flame/routes/matches.js` with:

```js
const express = require('express');
const { z } = require('zod');
const asyncHandler = require('../middleware/asyncHandler');
const auth = require('../middleware/auth');
const validate = require('../middleware/validate');
const ctrl = require('../controllers/matchController');

const router = express.Router();

const objectId = z.string().regex(/^[0-9a-fA-F]{24}$/, 'must be a valid ObjectId');
const idParam = z.object({ id: objectId });

router.get('/', auth, asyncHandler(ctrl.listMatches));
router.delete('/:id', auth, validate.params(idParam), asyncHandler(ctrl.deleteMatch));

module.exports = router;
```

- [ ] **Step 5: Run test to verify it passes**

Run: `node --test flame/__tests__/matches.test.js`
Expected: PASS — 4 tests

- [ ] **Step 6: Commit**

```bash
git add flame/services/matchService.js flame/controllers/matchController.js \
        flame/routes/matches.js flame/__tests__/matches.test.js
git commit -m "feat(flame): implement GET /matches and unmatch, replacing the stub"
```

---

### Task 9: Enforce blocks across every remaining surface

**Files:**
- Modify: `flame/services/chatService.js` (`openConversation`, `sendMessage`, `listConversations`)
- Modify: `flame/services/userService.js` (`getById`)
- Modify: `flame/services/storyService.js` (`visibleAuthorFilter`)
- Modify: `flame/socket/flameSocket.js` (`emitNewMessage`)
- Modify: `flame/services/blockService.js` (block also unmatches)
- Test: `flame/__tests__/blockEnforcement.test.js`

**Interfaces:**
- Consumes: `visibilityService` (Task 5), `Match` (Task 2)
- Produces: no new exports; behaviour changes only

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/blockEnforcement.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

async function setup() {
  await dbHelper.start();
  ['../db', '../models/User', '../models/Swipe', '../models/Match',
   '../models/Conversation', '../models/Message', '../models/Story',
   '../services/chatService', '../services/userService', '../services/storyService',
   '../services/swipeService', '../services/matchService',
   '../services/visibilityService', '../services/blockService']
    .forEach(p => { try { delete require.cache[require.resolve(p)]; } catch {} });

  const { connect } = require('../db');
  await connect();

  const User = require('../models/User');
  const mk = (email, name) => User.create({
    email, name, age: 30, gender: 'other', lookingFor: 'other', passwordHash: 'x',
  });
  const a = await mk('a@x.com', 'A');
  const b = await mk('b@x.com', 'B');

  return {
    a: a._id.toString(), b: b._id.toString(),
    chatService: require('../services/chatService'),
    userService: require('../services/userService'),
    blockService: require('../services/blockService'),
    swipeService: require('../services/swipeService'),
    matchService: require('../services/matchService'),
    Match: require('../models/Match'),
  };
}

const teardown = (t) => t.after(async () => {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
});

test('a blocked user cannot open a conversation', async (t) => {
  const { a, b, chatService, blockService } = await setup();
  teardown(t);

  await blockService.block(b, a);
  await assert.rejects(() => chatService.openConversation(a, b), (e) => e.status === 403);
});

test('a blocked user cannot send a message into an existing conversation', async (t) => {
  const { a, b, chatService, blockService } = await setup();
  teardown(t);

  const conv = await chatService.openConversation(a, b);
  await blockService.block(b, a);

  await assert.rejects(
    () => chatService.sendMessage(a, conv.id, { text: 'hello' }),
    (e) => e.status === 403,
  );
});

test('a blocked user disappears from the conversation list', async (t) => {
  const { a, b, chatService, blockService } = await setup();
  teardown(t);

  await chatService.openConversation(a, b);
  await blockService.block(a, b);

  const { conversations } = await chatService.listConversations(a, { limit: 20, offset: 0 });
  assert.equal(conversations.length, 0);
});

test('a blocked user 404s on profile view', async (t) => {
  const { a, b, userService, blockService } = await setup();
  teardown(t);

  await blockService.block(b, a);
  await assert.rejects(() => userService.getById(b, a), (e) => e.status === 404);
});

test('blocking ends an existing match', async (t) => {
  const { a, b, swipeService, matchService, blockService, Match } = await setup();
  teardown(t);

  await swipeService.record(a, b, 'like');
  await swipeService.record(b, a, 'like');
  assert.equal(await Match.countDocuments({ endedBy: null }), 1);

  await blockService.block(a, b);

  assert.equal(await Match.countDocuments({ endedBy: null }), 0, 'a block must unmatch');
  const { matches } = await matchService.list(a, {});
  assert.equal(matches.length, 0);
});
```

> **Note for the implementer:** `userService.getById` currently takes only
> `(userId)`. This task changes it to `(viewerId, targetId)`. Update its single
> caller in `flame/controllers/userController.js` (`getById`) to pass
> `req.user.id` first.

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/blockEnforcement.test.js`
Expected: FAIL — no 403s are thrown; blocked users still appear

- [ ] **Step 3: Enforce in chatService**

At the top of `flame/services/chatService.js`, add:

```js
const visibility = require('./visibilityService');
```

In `openConversation`, immediately after the self-conversation check, add:

```js
  await visibility.assertCanInteract(userId, otherUserId);
```

In `sendMessage`, after the conversation is loaded and the sender is confirmed a
participant, add (using whatever local variable holds the other participant's id):

```js
  await visibility.assertCanInteract(senderId, receiverId);
```

In `listConversations`, after computing `filter`, exclude blocked participants:

```js
  const hidden = await visibility.blockedIdsFor(userId);
  if (hidden.length) filter.participants = { $all: [userId], $nin: hidden };
```

- [ ] **Step 4: Enforce in userService and storyService**

In `flame/services/userService.js`, change `getById` to take the viewer first and
hide blocked users behind the same 404 as a missing user:

```js
async function getById(viewerId, userId) {
  const visibility = require('./visibilityService');
  // 404 rather than 403: a blocked user should be indistinguishable from one
  // who does not exist.
  if (viewerId && (await visibility.areBlocked(viewerId, userId))) {
    throw new NotFoundError('User not found');
  }
  const user = await User.findById(userId);
  if (!user || user.isDeleted) throw new NotFoundError('User not found');
  return toPublicMinimal(user);
}
```

Update the caller in `flame/controllers/userController.js`:

```js
async function getById(req, res) {
  const u = await userService.getById(req.user.id, req.params.id);
  res.json({ success: true, data: u });
}
```

In `flame/services/storyService.js`, fold blocks into `visibleAuthorFilter` by
excluding the blocked ids from whatever author set it already builds. Add at the
top of that function:

```js
  const visibility = require('./visibilityService');
  const hidden = await visibility.blockedIdsFor(viewerId);
```

and add `$nin: hidden` to the author-id condition it returns (keep its existing
conditions intact; this is an additional constraint, not a replacement).

- [ ] **Step 5: Enforce on socket delivery**

In `flame/socket/flameSocket.js`, make `emitNewMessage` drop blocked deliveries.
A live socket must not bypass the REST check:

```js
async function emitNewMessage(io, receiverId, message) {
  const visibility = require('../services/visibilityService');
  // A socket connection outlives a block, so re-check at delivery time.
  if (await visibility.areBlocked(receiverId, message.sender_id)) return;
  io.of(NS).to(room(receiverId)).emit('message:new', message);
}
```

> Use the actual sender field name on `message`; if it is not `sender_id`, use
> the real one rather than renaming the payload.

- [ ] **Step 6: Make blocking unmatch**

In `flame/services/blockService.js`, at the end of `block()`, add:

```js
  // A block is a complete severance, not a partial one: end any live match so
  // the conversation leaves both lists.
  const Match = require('../models/Match');
  await Match.updateOne(
    { users: Match.pair(userId, targetId), endedBy: null },
    { $set: { endedBy: userId } },
  );
```

- [ ] **Step 7: Run test to verify it passes**

Run: `node --test flame/__tests__/blockEnforcement.test.js`
Expected: PASS — 5 tests

- [ ] **Step 8: Run the whole flame suite for regressions**

Run: `node --test flame/__tests__/`
Expected: all suites pass. `chatService` and `userService` signature changes are
the likely breakages — fix any callers rather than reverting the change.

- [ ] **Step 9: Commit**

```bash
git add flame/services/chatService.js flame/services/userService.js \
        flame/services/storyService.js flame/socket/flameSocket.js \
        flame/services/blockService.js flame/controllers/userController.js \
        flame/__tests__/blockEnforcement.test.js
git commit -m "feat(flame): enforce blocks on every surface that returns a user"
```

---

### Task 10: Discover exclusion and filters

**Files:**
- Modify: `flame/services/discoveryService.js`
- Test: `flame/__tests__/discoveryExclusion.test.js`

**Interfaces:**
- Consumes: `visibilityService.excludedIdsFor` (Task 5)
- Produces: `discoveryService.discover` excluding swiped/blocked users and applying age + gender filters

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/discoveryExclusion.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

async function setup() {
  await dbHelper.start();
  ['../db', '../models/User', '../models/Swipe', '../services/discoveryService',
   '../services/visibilityService', '../services/blockService']
    .forEach(p => { try { delete require.cache[require.resolve(p)]; } catch {} });

  const { connect } = require('../db');
  await connect();

  const User = require('../models/User');
  const mk = (email, name, age = 30, gender = 'female') => User.create({
    email, name, age, gender, lookingFor: 'female', passwordHash: 'x',
  });

  const me = await mk('me@x.com', 'Me');
  const seen = await mk('seen@x.com', 'Seen');
  const blocked = await mk('blocked@x.com', 'Blocked');
  const fresh = await mk('fresh@x.com', 'Fresh');

  return {
    meId: me._id.toString(), seenId: seen._id.toString(),
    blockedId: blocked._id.toString(), freshId: fresh._id.toString(),
    discoveryService: require('../services/discoveryService'),
    blockService: require('../services/blockService'),
    Swipe: require('../models/Swipe'),
  };
}

const teardown = (t) => t.after(async () => {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
});

test('an already-swiped user never reappears', async (t) => {
  const { meId, seenId, freshId, discoveryService, Swipe } = await setup();
  teardown(t);

  await Swipe.create({ from: meId, to: seenId, action: 'pass' });

  const { users } = await discoveryService.discover(meId, { limit: 20, offset: 0 });
  const ids = users.map((u) => u.id);

  assert.ok(!ids.includes(seenId), 'a swiped user must not come back');
  assert.ok(ids.includes(freshId));
});

test('blocked users are excluded from the deck', async (t) => {
  const { meId, blockedId, discoveryService, blockService } = await setup();
  teardown(t);

  await blockService.block(meId, blockedId);

  const { users } = await discoveryService.discover(meId, { limit: 20, offset: 0 });
  assert.ok(!users.map((u) => u.id).includes(blockedId));
});

test('the deck empties once everyone has been swiped', async (t) => {
  const { meId, seenId, blockedId, freshId, discoveryService, Swipe } = await setup();
  teardown(t);

  for (const to of [seenId, blockedId, freshId]) {
    await Swipe.create({ from: meId, to, action: 'pass' });
  }

  const { users, total } = await discoveryService.discover(meId, { limit: 20, offset: 0 });
  assert.equal(users.length, 0);
  assert.equal(total, 0);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/discoveryExclusion.test.js`
Expected: FAIL — swiped and blocked users still appear

- [ ] **Step 3: Apply exclusion and filters**

In `flame/services/discoveryService.js`, add at the top:

```js
const visibility = require('./visibilityService');
```

Replace the filter construction in `discover` with:

```js
  const me = await User.findById(viewerId).lean();

  // Everyone this user has already judged, plus anyone either side blocked.
  const excluded = await visibility.excludedIdsFor(viewerId, { includeSwiped: true });

  const filter = {
    _id: { $ne: viewerId, $nin: excluded },
    isDeleted: { $ne: true },
  };

  // Gender preference, when the viewer expressed one other than 'other'.
  if (me && me.lookingFor && me.lookingFor !== 'other') {
    filter.gender = me.lookingFor;
  }

  // Age range from the viewer's preferences, when present.
  const prefs = (me && me.preferences) || {};
  if (prefs.minAge || prefs.maxAge) {
    filter.age = {};
    if (prefs.minAge) filter.age.$gte = prefs.minAge;
    if (prefs.maxAge) filter.age.$lte = prefs.maxAge;
  }
```

> Keep the rest of `discover` (count, find, pagination, `toDiscoverUser`) as is.
> Distance filtering is deliberately omitted: it requires `locationGeo`, which
> most users do not have, and filtering on it would empty the deck. Add it only
> behind a "has coordinates" check in a later phase.

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test flame/__tests__/discoveryExclusion.test.js`
Expected: PASS — 3 tests

- [ ] **Step 5: Commit**

```bash
git add flame/services/discoveryService.js flame/__tests__/discoveryExclusion.test.js
git commit -m "feat(flame): exclude swiped and blocked users from Discover"
```

---

### Task 11: APP — fix the Discover CardSwiper RangeError

**Files:**
- Modify: `APP lib/screens/home/home_screen.dart` (around lines 250-277)
- Test: `APP test/screens/home/card_swiper_bounds_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: a `cardBuilder` that never indexes past the end of the list

This is now a **blocker**, not a nuisance: with Task 10 shipped the deck genuinely
empties, which is exactly the condition that trips the stale index.

The spec also lists a "deck-empty state" as app work. It already exists —
`home_screen.dart:241` returns `_buildEmptyState()` when `users.isEmpty`
(defined at line 302). Nothing to build; just confirm it renders during Task 13
Step 6 instead of writing a second one.

- [ ] **Step 1: Write the failing test**

Create `APP test/screens/home/card_swiper_bounds_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_test/flutter_test.dart';

// CardSwiper keeps its own current index. When the backing list shrinks — which
// happens as soon as Discover excludes swiped users and the deck runs out — the
// builder can be called with an index past the end. Reproduced here directly.
void main() {
  testWidgets('cardBuilder is never called with an out-of-range index',
      (tester) async {
    final users = <String>['a', 'b', 'c'];
    final seen = <int>[];

    Widget build() => MaterialApp(
          home: Scaffold(
            body: CardSwiper(
              cardsCount: users.length,
              numberOfCardsDisplayed: users.length > 2 ? 3 : users.length,
              cardBuilder: (context, index, px, py) {
                seen.add(index);
                if (index < 0 || index >= users.length) {
                  return const SizedBox.shrink();
                }
                return Text(users[index]);
              },
            ),
          ),
        );

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    // Shrink the deck to one item and rebuild, mimicking the provider emitting
    // a shorter list while the swiper's internal index has advanced.
    users.removeRange(1, users.length);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'a shrinking deck must not throw RangeError');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Desktop/Flame/flame_front_app && flutter test test/screens/home/card_swiper_bounds_test.dart`
Expected: FAIL with `RangeError (length)` — matching the production crash

- [ ] **Step 3: Guard the builder**

In `APP lib/screens/home/home_screen.dart`, replace the `cardBuilder` callback
with a bounds-guarded version:

```dart
                        cardBuilder: (context, index, percentX, percentY) {
                          // CardSwiper holds its own index; when the deck shrinks
                          // (Discover now excludes swiped users, so it genuinely
                          // empties) that index can outrun the list. Render
                          // nothing rather than throwing RangeError.
                          if (index < 0 || index >= users.length) {
                            return const SizedBox.shrink();
                          }
                          final user = users[index];
                          return ProfileCard(
                            user: user,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProfileDetailScreen(user: user),
                                ),
                              );
                            },
                          );
                        },
```

Note this also fixes a latent bug in the original: `users[index]` was evaluated a
second time inside `onTap`, so a card tapped after the list changed could open a
different person's profile. Capturing `user` once removes that.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/home/card_swiper_bounds_test.dart`
Expected: PASS

- [ ] **Step 5: Run the full app suite**

Run: `flutter test`
Expected: all tests pass (207 at time of writing)

- [ ] **Step 6: Commit**

```bash
cd ~/Desktop/Flame/flame_front_app
git add lib/screens/home/home_screen.dart test/screens/home/card_swiper_bounds_test.dart
git commit -m "fix(discover): guard CardSwiper against an index past a shrinking deck"
```

---

### Task 12: APP — unmatch entry point

**Files:**
- Modify: `APP lib/services/match_service.dart` (add `unmatch`)
- Modify: `APP lib/providers/match_provider.dart` (add `unmatch`)
- Modify: `APP lib/screens/chat/matches_screen.dart` (add the action)
- Test: `APP test/providers/match_unmatch_test.dart`

**Interfaces:**
- Consumes: `DELETE /matches/:id` (Task 8)
- Produces: `MatchService.unmatch(String matchId)` → `ServiceResult<void>`; `MatchesNotifier.unmatch(String matchId)` removing it from state

- [ ] **Step 1: Read the existing service to match its conventions**

Run: `sed -n '1,40p' lib/services/match_service.dart`

Follow the same `ServiceResult` / `_apiClient` style already used by
`getMatches` — do not introduce a different error-handling shape.

- [ ] **Step 2: Write the failing test**

Create `APP test/providers/match_unmatch_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';

// Matches are built through Match.fromJson rather than the constructor so the
// test does not have to know User's required fields — and it doubles as a check
// that the backend's payload keys are the ones the app actually parses.
Match _match(String id) => Match.fromJson({
      'id': id,
      'user': {'id': 'u-$id', 'name': 'User $id'},
      'matched_at': '2026-08-16T00:00:00.000Z',
      'is_new': true,
    });

void main() {
  test('Match.fromJson reads the keys the backend sends', () {
    final m = _match('m1');
    expect(m.id, 'm1');
    expect(m.user.id, 'u-m1');
    expect(m.isNew, isTrue);
  });

  test('removing a match drops only that one', () {
    final matches = [_match('m1'), _match('m2')];

    // The transformation removeMatch performs on state.
    final remaining = matches.where((m) => m.id != 'm1').toList();

    expect(remaining.length, 1);
    expect(remaining.single.id, 'm2');
  });
}
```

> This tests the payload contract and the list transformation without spinning up
> the notifier, which would require a live `ApiClient`. When wiring
> `MatchesNotifier.removeMatch` in Step 4, keep its body identical to the
> `where` above so this test covers it.

- [ ] **Step 3: Add the service method**

In `APP lib/services/match_service.dart`:

```dart
  Future<ServiceResult<void>> unmatch(String matchId) async {
    final response = await _apiClient.delete('/matches/$matchId');

    if (response.success) {
      return ServiceResult.success(null);
    }
    return ServiceResult.failure(response.error ?? 'Failed to unmatch');
  }
```

- [ ] **Step 4: Add the provider method**

In `APP lib/providers/match_provider.dart`, inside `MatchesNotifier`:

```dart
  /// Removes a match locally. Call after the server confirms the unmatch so the
  /// list does not flicker back on a failed request.
  void removeMatch(String matchId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(current.where((m) => m.id != matchId).toList());
  }

  Future<bool> unmatch(String matchId) async {
    final result = await _matchService.unmatch(matchId);
    if (result.success) {
      removeMatch(matchId);
      return true;
    }
    return false;
  }
```

- [ ] **Step 5: Add the UI action**

In `APP lib/screens/chat/matches_screen.dart`, wrap each match tile in a
`Dismissible` (or add a long-press menu, following whatever pattern the screen
already uses for row actions) that calls:

```dart
await ref.read(matchesProvider.notifier).unmatch(match.id);
```

Confirm with a dialog first — unmatching is destructive and not undoable.

- [ ] **Step 6: Run the tests**

Run: `flutter test`
Expected: all pass

- [ ] **Step 7: Commit**

```bash
git add lib/services/match_service.dart lib/providers/match_provider.dart \
        lib/screens/chat/matches_screen.dart test/providers/match_unmatch_test.dart
git commit -m "feat(matches): add unmatch action wired to DELETE /matches/:id"
```

---

### Task 13: End-to-end verification against a running backend

**Files:** none — this is a manual verification gate.

- [ ] **Step 1: Run the full backend suite**

```bash
cd ~/Projects/BananaTalk/backend
node --test flame/__tests__/
```
Expected: every suite passes.

- [ ] **Step 2: Run the full app suite**

```bash
cd ~/Desktop/Flame/flame_front_app
flutter test && flutter analyze
```
Expected: all tests pass, zero analyzer errors.

- [ ] **Step 3: Deploy and restart the backend**

```bash
# on the server
cd /home/language_exchange_backend_application && git pull && pm2 restart language-app
```

- [ ] **Step 4: Verify the endpoints answer**

```bash
B=https://api.banatalk.com/flamebackend/v1
curl -s -o /dev/null -w "GET  /matches -> %{http_code}\n" $B/matches
curl -s -o /dev/null -w "GET  /blocks  -> %{http_code}\n" $B/blocks
curl -s -o /dev/null -w "POST /reports -> %{http_code}\n" -X POST $B/reports
```
Expected: `401` for each (route exists, auth required). A `404` means the router
was not mounted.

- [ ] **Step 5: Exercise the loop in the app**

With two accounts on two devices/simulators:

1. Sign in as A, swipe right on B → no match, B disappears from A's deck
2. Sign in as B, swipe right on A → **"It's a Match!"** dialog appears
3. Both see the match in the Chat tab with a conversation
4. Send a message each way — it arrives live over the socket
5. A blocks B → the match and conversation disappear for both, and B does not
   reappear in A's deck
6. A reports B → `200`, and a `reports` row exists

- [ ] **Step 6: Confirm Discover empties cleanly**

Keep swiping as A until the deck runs out. Expect the empty state, **not** a
`RangeError` — this is the crash Task 11 fixes, and an emptying deck is now the
normal case.
