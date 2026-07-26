# Chat-BE-1 — Flame Messaging Backend Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the flame messaging backend core: `Conversation` + `Message` models and the REST endpoints to list conversations, open a DM, read a thread, send a text message, and mark a conversation read — replacing the empty `/conversations` stub.

**Architecture:** Follows the flame sub-app pattern exactly: Mongoose models on the isolated `getConn()` connection (participant/sender ids stored as **String**, camelCase schema fields), a `chatService` holding all logic + snake_case response shapers, a thin `chatController`, and `routes/conversations.js` with `zod` validation. Tests use `node:test` + `supertest` + `mongodb-memory-server`, mirroring `flame/__tests__/stories.test.js`.

**Tech Stack:** Node/Express, Mongoose, zod, `node:test`.

## Global Constraints — READ FIRST

- **Repo & branch:** ALL work happens in `/Users/firdavsmutalipov/Projects/BananaTalk/backend` on branch **`feat/flame-chat`** (already created). NEVER commit to `main` (it auto-deploys to prod). Confirm `git -C /Users/firdavsmutalipov/Projects/BananaTalk/backend rev-parse --abbrev-ref HEAD` prints `feat/flame-chat` before committing.
- **Ids are Strings.** Store `participants`, `sender`, `receiver`, `unreadCount[].user`, `reactions[].user`, `conversationId`, `replyTo` as `String` (holding `_id.toString()`). No `ObjectId` refs, no `populate()` — the flame codebase never uses them. `req.user.id` is a string.
- **Schema fields are camelCase; API responses are snake_case.** The service's `toConversation`/`toMessage` shapers convert (e.g. `lastMessageAt` → `last_message_at`). New flame endpoints MUST emit snake_case.
- **Envelope:** success `res.json({ success: true, data })` (create → `201`); list endpoints nest `pagination: { total, limit, offset, has_more }` inside `data`. Errors are thrown as `FlameError`/`NotFoundError`/`ValidationError` (from `../utils/errors`) and rendered by `middleware/error.js`. There is **no** `ForbiddenError` class — use `new FlameError('FORBIDDEN', msg, 403)`.
- **Model registration:** `module.exports = getConn().model('Name', schema)` with explicit `collection` + `timestamps`.
- **Routes are already mounted:** `flame/index.js` already has `router.use('/conversations', require('./routes/conversations'))`. Replacing the file's contents needs NO index.js change. Nested `/:id/messages` and `/:id/read` live inside `routes/conversations.js`.
- **Test command** (run from `/Users/firdavsmutalipov/Projects/BananaTalk/backend`): `node --test flame/__tests__/<file>.test.js`; whole suite `node --test flame/__tests__/*.test.js`.
- **Do not break** `flame/__tests__/endpoints.test.js` — its `GET /conversations → valid empty page` test must still pass (a user with no conversations legitimately gets `data.conversations: []` + the same pagination shape).

**Reference files to mirror (read them):** `flame/models/RefreshToken.js` (model pattern), `flame/services/storyService.js` (service shape + `FlameError('FORBIDDEN',...,403)` + `toX` shapers), `flame/routes/stories.js` (zod `validate` usage), `flame/controllers/storyController.js` (thin controllers), `flame/__tests__/stories.test.js` (test harness: `setup()`/`teardown()`/`registerUser()`), `flame/middleware/{auth,validate,asyncHandler}.js`, `flame/utils/errors.js`.

---

### Task 1: Conversation + Message models

**Files (all under `/Users/firdavsmutalipov/Projects/BananaTalk/backend/`):**
- Create: `flame/models/Conversation.js`
- Create: `flame/models/Message.js`
- Test: `flame/__tests__/chatModels.test.js`

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/chatModels.test.js`, mirroring the DB bootstrap of `flame/__tests__/refreshTokenModel.test.js` (start in-memory Mongo, `connect()`, exercise the model, `close()`/stop). Use this content:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

async function setup() {
  await dbHelper.start();
  ['../db', '../models/Conversation', '../models/Message'].forEach((p) => {
    try { delete require.cache[require.resolve(p)]; } catch {}
  });
  const { connect } = require('../db');
  await connect();
  return {
    Conversation: require('../models/Conversation'),
    Message: require('../models/Message'),
  };
}
async function teardown() {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
}

test('Conversation stores two string participants with defaults', async (t) => {
  const { Conversation } = await setup();
  t.after(teardown);

  const c = await Conversation.create({
    participants: ['a1', 'b2'],
    unreadCount: [{ user: 'a1', count: 0 }, { user: 'b2', count: 0 }],
  });
  assert.deepEqual(c.participants, ['a1', 'b2']);
  assert.equal(c.lastMessage, null);
  assert.equal(c.lastMessageAt, null);
  assert.equal(c.unreadCount.length, 2);
  assert.ok(c.createdAt instanceof Date);
});

test('Message defaults: type text, unread, no reactions', async (t) => {
  const { Message } = await setup();
  t.after(teardown);

  const m = await Message.create({
    conversationId: 'c1', sender: 'a1', receiver: 'b2', text: 'hi',
  });
  assert.equal(m.messageType, 'text');
  assert.equal(m.read, false);
  assert.equal(m.readAt, null);
  assert.deepEqual(m.reactions, []);
  assert.equal(m.isDeleted, false);
  assert.equal(m.text, 'hi');
  assert.ok(m.createdAt instanceof Date);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/chatModels.test.js`
Expected: FAIL — the model modules don't exist (require error).

- [ ] **Step 3: Create the models**

`flame/models/Conversation.js`:

```js
const mongoose = require('mongoose');
const { getConn } = require('../db');

const unreadSchema = new mongoose.Schema(
  { user: { type: String, required: true }, count: { type: Number, default: 0 } },
  { _id: false },
);

const conversationSchema = new mongoose.Schema(
  {
    participants: {
      type: [String],
      required: true,
      validate: {
        validator: (v) => Array.isArray(v) && v.length === 2,
        message: 'participants must have exactly 2 users',
      },
      index: true,
    },
    lastMessage: { type: String, default: null },
    lastMessageAt: { type: Date, default: null },
    unreadCount: { type: [unreadSchema], default: [] },
  },
  { timestamps: true, collection: 'conversations' },
);

module.exports = getConn().model('Conversation', conversationSchema);
```

`flame/models/Message.js`:

```js
const mongoose = require('mongoose');
const { getConn } = require('../db');

const reactionSchema = new mongoose.Schema(
  { user: { type: String, required: true }, emoji: { type: String, required: true } },
  { _id: false },
);

const messageSchema = new mongoose.Schema(
  {
    conversationId: { type: String, required: true, index: true },
    sender: { type: String, required: true, index: true },
    receiver: { type: String, required: true },
    text: { type: String, default: '', maxlength: 2000 },
    messageType: { type: String, enum: ['text'], default: 'text' },
    reactions: { type: [reactionSchema], default: [] },
    replyTo: { type: String, default: null },
    read: { type: Boolean, default: false },
    readAt: { type: Date, default: null },
    isDeleted: { type: Boolean, default: false },
    deletedFor: { type: [String], default: [] },
  },
  { timestamps: true, collection: 'messages' },
);

module.exports = getConn().model('Message', messageSchema);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test flame/__tests__/chatModels.test.js`
Expected: PASS (both tests).

- [ ] **Step 5: Commit** (confirm branch first)

```bash
cd /Users/firdavsmutalipov/Projects/BananaTalk/backend
git rev-parse --abbrev-ref HEAD   # must print feat/flame-chat
git add flame/models/Conversation.js flame/models/Message.js flame/__tests__/chatModels.test.js
git commit -m "feat(flame-chat): Conversation + Message models"
```

---

### Task 2: chatService + controller + routes (list, open, thread, send, read)

**Files (under `/Users/firdavsmutalipov/Projects/BananaTalk/backend/`):**
- Create: `flame/services/chatService.js`
- Create: `flame/controllers/chatController.js`
- Replace: `flame/routes/conversations.js` (currently the empty stub)
- Test: `flame/__tests__/conversations.test.js`

**Interfaces:**
- `chatService` exports `openConversation(userId, otherUserId)`, `listConversations(userId, {limit, offset})`,
  `getMessages(userId, conversationId, {limit, offset})`, `sendMessage(userId, conversationId, {text})`,
  `markRead(userId, conversationId)`, plus `toConversation`, `toMessage`.
- Endpoints (auth required on all): `GET /conversations`, `POST /conversations` (`{user_id}`),
  `GET /conversations/:id/messages`, `POST /conversations/:id/messages` (`{text}`),
  `PUT /conversations/:id/read`.

- [ ] **Step 1: Write the failing endpoint test**

Create `flame/__tests__/conversations.test.js` by COPYING the `setup()`/`teardown()`/`registerUser()`
harness verbatim from `flame/__tests__/stories.test.js` (same env vars, same `buildApp`), then EXTEND
the `require.cache` bust list in `setup()` to also include:
`'../models/Conversation'`, `'../models/Message'`, `'../services/chatService'`,
`'../controllers/chatController'`, `'../routes/conversations'`. Then add these tests (they assume the
harness's `registerUser(app, email)` returns `{ token, id }`):

```js
const authH = (token) => ({ Authorization: `Bearer ${token}` });

test('open → send → list → thread → mark read (happy path)', async (t) => {
  const app = await setup();
  t.after(teardown);
  const a = await registerUser(app, 'a@x.com');
  const b = await registerUser(app, 'b@x.com');

  // A opens a conversation with B
  const open = await request(app)
    .post('/flamebackend/v1/conversations')
    .set(authH(a.token))
    .send({ user_id: b.id })
    .expect(201);
  const convId = open.body.data.id;
  assert.equal(open.body.data.other_user_id, b.id);
  assert.equal(open.body.data.unread_count, 0);

  // Opening again returns the SAME conversation (no duplicate)
  const open2 = await request(app)
    .post('/flamebackend/v1/conversations')
    .set(authH(a.token))
    .send({ user_id: b.id })
    .expect(201);
  assert.equal(open2.body.data.id, convId);

  // A sends a message
  const send = await request(app)
    .post(`/flamebackend/v1/conversations/${convId}/messages`)
    .set(authH(a.token))
    .send({ text: 'hello b' })
    .expect(201);
  assert.equal(send.body.data.text, 'hello b');
  assert.equal(send.body.data.sender_id, a.id);
  assert.equal(send.body.data.receiver_id, b.id);
  assert.equal(send.body.data.message_type, 'text');

  // B lists conversations → sees it with unread_count 1 and the last message
  const listB = await request(app)
    .get('/flamebackend/v1/conversations')
    .set(authH(b.token))
    .expect(200);
  assert.equal(listB.body.data.conversations.length, 1);
  assert.equal(listB.body.data.conversations[0].unread_count, 1);
  assert.equal(listB.body.data.conversations[0].last_message.text, 'hello b');
  assert.equal(listB.body.data.pagination.total, 1);

  // B reads the thread (newest first) and marks read
  const thread = await request(app)
    .get(`/flamebackend/v1/conversations/${convId}/messages`)
    .set(authH(b.token))
    .expect(200);
  assert.equal(thread.body.data.messages.length, 1);
  assert.equal(thread.body.data.messages[0].text, 'hello b');

  await request(app)
    .put(`/flamebackend/v1/conversations/${convId}/read`)
    .set(authH(b.token))
    .expect(200);

  const listB2 = await request(app)
    .get('/flamebackend/v1/conversations')
    .set(authH(b.token))
    .expect(200);
  assert.equal(listB2.body.data.conversations[0].unread_count, 0);
});

test('a non-participant is forbidden from the thread', async (t) => {
  const app = await setup();
  t.after(teardown);
  const a = await registerUser(app, 'a@x.com');
  const b = await registerUser(app, 'b@x.com');
  const c = await registerUser(app, 'c@x.com');
  const open = await request(app).post('/flamebackend/v1/conversations')
    .set(authH(a.token)).send({ user_id: b.id }).expect(201);
  await request(app)
    .get(`/flamebackend/v1/conversations/${open.body.data.id}/messages`)
    .set(authH(c.token))
    .expect(403);
});

test('unauthenticated requests are rejected', async (t) => {
  const app = await setup();
  t.after(teardown);
  await request(app).get('/flamebackend/v1/conversations').expect(401);
});

test('empty text is rejected (422)', async (t) => {
  const app = await setup();
  t.after(teardown);
  const a = await registerUser(app, 'a@x.com');
  const b = await registerUser(app, 'b@x.com');
  const open = await request(app).post('/flamebackend/v1/conversations')
    .set(authH(a.token)).send({ user_id: b.id }).expect(201);
  await request(app)
    .post(`/flamebackend/v1/conversations/${open.body.data.id}/messages`)
    .set(authH(a.token))
    .send({ text: '' })
    .expect(422);
});

test('opening a conversation with a non-existent user is 404', async (t) => {
  const app = await setup();
  t.after(teardown);
  const a = await registerUser(app, 'a@x.com');
  await request(app).post('/flamebackend/v1/conversations')
    .set(authH(a.token))
    .send({ user_id: '0123456789abcdef01234567' })
    .expect(404);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/conversations.test.js`
Expected: FAIL — service/controller/routes not implemented (the POST returns the old stub / 404s).

- [ ] **Step 3: Create the service** — `flame/services/chatService.js`:

```js
const Conversation = require('../models/Conversation');
const Message = require('../models/Message');
const User = require('../models/User');
const { NotFoundError, ValidationError, FlameError } = require('../utils/errors');

function toMessage(m) {
  return {
    id: m._id.toString(),
    conversation_id: m.conversationId,
    sender_id: m.sender,
    receiver_id: m.receiver,
    text: m.text,
    message_type: m.messageType,
    reactions: (m.reactions || []).map((r) => ({ user_id: r.user, emoji: r.emoji })),
    reply_to: m.replyTo || null,
    read: m.read,
    read_at: m.readAt ? m.readAt.toISOString() : null,
    created_at: m.createdAt ? m.createdAt.toISOString() : null,
  };
}

function toConversation(c, forUserId, lastMessageDoc) {
  const other = c.participants.find((p) => p !== forUserId) || null;
  const mine = (c.unreadCount || []).find((u) => u.user === forUserId);
  return {
    id: c._id.toString(),
    other_user_id: other,
    last_message: lastMessageDoc ? toMessage(lastMessageDoc) : null,
    last_message_at: c.lastMessageAt ? c.lastMessageAt.toISOString() : null,
    unread_count: mine ? mine.count : 0,
    created_at: c.createdAt ? c.createdAt.toISOString() : null,
  };
}

async function _findConversation(conversationId) {
  let conv = null;
  try { conv = await Conversation.findById(conversationId); } catch (_) { conv = null; }
  if (!conv) throw new NotFoundError('conversation not found');
  return conv;
}

function _assertParticipant(conv, userId) {
  if (!conv.participants.includes(userId)) {
    throw new FlameError('FORBIDDEN', 'not your conversation', 403);
  }
}

async function openConversation(userId, otherUserId) {
  if (otherUserId === userId) throw new ValidationError('cannot open a conversation with yourself');
  let other = null;
  try { other = await User.findById(otherUserId).lean(); } catch (_) { other = null; }
  if (!other) throw new NotFoundError('user not found');

  let conv = await Conversation.findOne({ participants: { $all: [userId, otherUserId], $size: 2 } });
  if (!conv) {
    conv = await Conversation.create({
      participants: [userId, otherUserId],
      unreadCount: [{ user: userId, count: 0 }, { user: otherUserId, count: 0 }],
    });
  }
  return toConversation(conv, userId, null);
}

async function listConversations(userId, { limit, offset }) {
  const filter = { participants: userId };
  const total = await Conversation.countDocuments(filter);
  const convs = await Conversation.find(filter)
    .sort({ lastMessageAt: -1, updatedAt: -1 })
    .skip(offset)
    .limit(limit);
  const conversations = [];
  for (const c of convs) {
    const lm = c.lastMessage ? await Message.findById(c.lastMessage) : null;
    conversations.push(toConversation(c, userId, lm));
  }
  return { conversations, total };
}

async function getMessages(userId, conversationId, { limit, offset }) {
  const conv = await _findConversation(conversationId);
  _assertParticipant(conv, userId);
  const filter = { conversationId, isDeleted: false };
  const total = await Message.countDocuments(filter);
  const msgs = await Message.find(filter).sort({ createdAt: -1 }).skip(offset).limit(limit);
  return { messages: msgs.map(toMessage), total };
}

async function sendMessage(userId, conversationId, { text }) {
  const conv = await _findConversation(conversationId);
  _assertParticipant(conv, userId);
  const receiver = conv.participants.find((p) => p !== userId);
  const msg = await Message.create({
    conversationId, sender: userId, receiver, text, messageType: 'text',
  });
  conv.lastMessage = msg._id.toString();
  conv.lastMessageAt = msg.createdAt;
  const entry = conv.unreadCount.find((u) => u.user === receiver);
  if (entry) entry.count += 1;
  else conv.unreadCount.push({ user: receiver, count: 1 });
  await conv.save();
  return toMessage(msg);
}

async function markRead(userId, conversationId) {
  const conv = await _findConversation(conversationId);
  _assertParticipant(conv, userId);
  const result = await Message.updateMany(
    { conversationId, receiver: userId, read: false },
    { $set: { read: true, readAt: new Date() } },
  );
  const entry = conv.unreadCount.find((u) => u.user === userId);
  if (entry) { entry.count = 0; await conv.save(); }
  return { marked: result.modifiedCount || 0 };
}

module.exports = {
  openConversation, listConversations, getMessages, sendMessage, markRead,
  toConversation, toMessage,
};
```

- [ ] **Step 4: Create the controller** — `flame/controllers/chatController.js`:

```js
const chatService = require('../services/chatService');

async function listConversations(req, res) {
  const limit = parseInt(req.query.limit, 10) || 20;
  const offset = parseInt(req.query.offset, 10) || 0;
  const { conversations, total } = await chatService.listConversations(req.user.id, { limit, offset });
  res.json({
    success: true,
    data: {
      conversations,
      pagination: { total, limit, offset, has_more: offset + conversations.length < total },
    },
  });
}

async function openConversation(req, res) {
  const data = await chatService.openConversation(req.user.id, req.body.user_id);
  res.status(201).json({ success: true, data });
}

async function getMessages(req, res) {
  const limit = parseInt(req.query.limit, 10) || 30;
  const offset = parseInt(req.query.offset, 10) || 0;
  const { messages, total } = await chatService.getMessages(req.user.id, req.params.id, { limit, offset });
  res.json({
    success: true,
    data: {
      messages,
      pagination: { total, limit, offset, has_more: offset + messages.length < total },
    },
  });
}

async function sendMessage(req, res) {
  const data = await chatService.sendMessage(req.user.id, req.params.id, { text: req.body.text });
  res.status(201).json({ success: true, data });
}

async function markRead(req, res) {
  const data = await chatService.markRead(req.user.id, req.params.id);
  res.json({ success: true, data });
}

module.exports = { listConversations, openConversation, getMessages, sendMessage, markRead };
```

- [ ] **Step 5: Replace the routes** — overwrite `flame/routes/conversations.js`:

```js
const express = require('express');
const { z } = require('zod');
const asyncHandler = require('../middleware/asyncHandler');
const auth = require('../middleware/auth');
const validate = require('../middleware/validate');
const ctrl = require('../controllers/chatController');

const router = express.Router();

const objectId = z.string().regex(/^[0-9a-fA-F]{24}$/, 'must be a valid ObjectId');
const idParam = z.object({ id: objectId });
const openSchema = z.object({ user_id: objectId });
const sendSchema = z.object({ text: z.string().min(1).max(2000) });

router.get('/', auth, asyncHandler(ctrl.listConversations));
router.post('/', auth, validate.body(openSchema), asyncHandler(ctrl.openConversation));
router.get('/:id/messages', auth, validate.params(idParam), asyncHandler(ctrl.getMessages));
router.post('/:id/messages', auth, validate.params(idParam), validate.body(sendSchema), asyncHandler(ctrl.sendMessage));
router.put('/:id/read', auth, validate.params(idParam), asyncHandler(ctrl.markRead));

module.exports = router;
```

Verify against the actual `flame/middleware/validate.js` and `flame/routes/stories.js` that the
`validate.body`/`validate.params` call form matches (adjust the call syntax if the real API differs —
the schemas and routes stay the same).

- [ ] **Step 6: Run the test to verify it passes**

Run: `node --test flame/__tests__/conversations.test.js`
Expected: PASS (all 5 tests).

- [ ] **Step 7: Confirm the existing stub test still passes**

Run: `node --test flame/__tests__/endpoints.test.js`
Expected: PASS — `GET /conversations → valid empty page` still holds (a fresh user gets
`data.conversations: []`). If it fails only because the new route now transitively requires the new
models and the test's `require.cache` list is stale, add `'../models/Conversation'`,
`'../models/Message'`, `'../services/chatService'`, `'../controllers/chatController'` to
endpoints.test.js's existing bust list — the SMALLEST change that makes it green, nothing else.

- [ ] **Step 8: Commit**

```bash
cd /Users/firdavsmutalipov/Projects/BananaTalk/backend
git rev-parse --abbrev-ref HEAD   # must print feat/flame-chat
git add flame/services/chatService.js flame/controllers/chatController.js flame/routes/conversations.js flame/__tests__/conversations.test.js
# include flame/__tests__/endpoints.test.js ONLY if Step 7 required the cache-bust edit
git commit -m "feat(flame-chat): conversation + message REST (list, open, thread, send, read)"
```

---

### Task 3: Full flame suite verification

**Files:** none (verification only).

- [ ] **Step 1: Run the whole flame test suite**

Run (from `/Users/firdavsmutalipov/Projects/BananaTalk/backend`): `node --test flame/__tests__/*.test.js`
Expected: PASS — all pre-existing flame tests plus the two new files (`chatModels.test.js`,
`conversations.test.js`) green. No regressions.

- [ ] **Step 2: Confirm branch + clean state**

Run: `git -C /Users/firdavsmutalipov/Projects/BananaTalk/backend status --short && git -C /Users/firdavsmutalipov/Projects/BananaTalk/backend log --oneline c97a1cc..HEAD`
Expected: working tree clean; the log shows exactly the Task 1 + Task 2 commits on `feat/flame-chat`.

---

## Self-Review

**Spec coverage (Chat-BE-1):** models + list/open/thread/send/mark-read → Tasks 1-2, all endpoint-
tested. ✅ Reactions/reply are Chat-BE-2 (not here). ✅

**Placeholder scan:** No TBD/TODO — full model/service/controller/route/test code provided. The only
conditional is Step 7's cache-bust (a concrete, bounded fallback), and one instruction to verify the
`validate.*` call form against the real middleware. ✅

**Consistency:** ids are `String` throughout (models, service, shapers, tests use string ids like
`'a1'` and real `registerUser` ids). Envelope + pagination `{total,limit,offset,has_more}` match the
flame convention and the controller output. `FlameError('FORBIDDEN',...,403)` (no ForbiddenError
class) matches `utils/errors.js`. Service method signatures match the controller call sites and the
Interfaces block. snake_case in every response shaper. ✅

**Safety:** all work on `feat/flame-chat`, never `main`; each commit step re-checks the branch. ✅
