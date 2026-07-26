# Chat-BE-2 — Reactions + Reply Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two BananaTalk-parity messaging features to the flame backend on top of Chat-BE-1: **reply/quote** (send a message that references an earlier one) and **reactions** (one emoji per user per message, add/replace/remove).

**Architecture:** Extend the existing `chatService`/`chatController`. Reply is an optional `reply_to` on the existing send endpoint. Reactions get a new `routes/messages.js` mounted at `/messages`, with participant-scoped authorization (only the message's sender or receiver may react).

**Tech Stack:** Node/Express, Mongoose, zod, `node:test`.

## Global Constraints — READ FIRST

- **Repo & branch:** ALL work in `/Users/firdavsmutalipov/Projects/BananaTalk/backend` on branch **`feat/flame-chat`** (BE-1 committed there: `1e3c225`, `fd38f2a`). NEVER commit to `main`. Re-check the branch before every commit.
- Builds directly on BE-1: `flame/models/Message.js` already has `reactions: [{user, emoji}]` and `replyTo: String`; `flame/services/chatService.js` already has `toMessage`, `sendMessage`, `_findConversation`, `_assertParticipant`.
- **Ids are Strings; responses snake_case; envelope `{success, data}`; errors via `FlameError('FORBIDDEN',...,403)` / `NotFoundError` / `ValidationError`.** `toMessage` already emits `reactions: [{user_id, emoji}]` and `reply_to`.
- Test command from `/Users/firdavsmutalipov/Projects/BananaTalk/backend`: `node --test flame/__tests__/<file>.test.js`. Each `test()` spins up its own in-memory Mongo — runs are slow (a minute+), that's expected; use a generous timeout.
- Reference: `flame/__tests__/conversations.test.js` (BE-1) for the exact `setup()/teardown()/registerUser()` harness + `authH` helper to copy.

---

### Task 1: Reply support on send

**Files (under `/Users/firdavsmutalipov/Projects/BananaTalk/backend/`):**
- Modify: `flame/services/chatService.js` (`sendMessage`)
- Modify: `flame/routes/conversations.js` (`sendSchema`)
- Modify: `flame/controllers/chatController.js` (`sendMessage` handler)
- Test: `flame/__tests__/conversations.test.js` (add reply tests)

**Interfaces:** `sendMessage(userId, conversationId, { text, replyTo })` — `replyTo` optional; when present it must be an existing message in the SAME conversation, else `ValidationError` (422). Response `reply_to` echoes the id.

- [ ] **Step 1: Add failing tests** to `flame/__tests__/conversations.test.js` (reuse its harness/`authH`):

```js
test('reply_to references an earlier message in the same conversation', async (t) => {
  const app = await setup();
  t.after(teardown);
  const a = await registerUser(app, 'a@x.com');
  const b = await registerUser(app, 'b@x.com');
  const open = await request(app).post('/flamebackend/v1/conversations')
    .set(authH(a.token)).send({ user_id: b.id }).expect(201);
  const conv = open.body.data.id;
  const first = await request(app).post(`/flamebackend/v1/conversations/${conv}/messages`)
    .set(authH(a.token)).send({ text: 'original' }).expect(201);

  const reply = await request(app).post(`/flamebackend/v1/conversations/${conv}/messages`)
    .set(authH(b.token)).send({ text: 'quoted!', reply_to: first.body.data.id }).expect(201);
  assert.equal(reply.body.data.reply_to, first.body.data.id);
});

test('reply_to pointing at another conversation is rejected (422)', async (t) => {
  const app = await setup();
  t.after(teardown);
  const a = await registerUser(app, 'a@x.com');
  const b = await registerUser(app, 'b@x.com');
  const c = await registerUser(app, 'c@x.com');
  const convAB = (await request(app).post('/flamebackend/v1/conversations')
    .set(authH(a.token)).send({ user_id: b.id }).expect(201)).body.data.id;
  const convAC = (await request(app).post('/flamebackend/v1/conversations')
    .set(authH(a.token)).send({ user_id: c.id }).expect(201)).body.data.id;
  const msgInAC = await request(app).post(`/flamebackend/v1/conversations/${convAC}/messages`)
    .set(authH(a.token)).send({ text: 'in AC' }).expect(201);

  await request(app).post(`/flamebackend/v1/conversations/${convAB}/messages`)
    .set(authH(a.token)).send({ text: 'bad reply', reply_to: msgInAC.body.data.id })
    .expect(422);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test flame/__tests__/conversations.test.js`
Expected: FAIL — reply currently ignored (first test would show `reply_to: null`; second would send 201 instead of 422).

- [ ] **Step 3: Implement in `chatService.js`** — replace the `sendMessage` function with:

```js
async function sendMessage(userId, conversationId, { text, replyTo }) {
  const conv = await _findConversation(conversationId);
  _assertParticipant(conv, userId);
  if (replyTo) {
    let parent = null;
    try { parent = await Message.findById(replyTo); } catch (_) { parent = null; }
    if (!parent || parent.conversationId !== conversationId) {
      throw new ValidationError('reply_to must be a message in this conversation');
    }
  }
  const receiver = conv.participants.find((p) => p !== userId);
  const msg = await Message.create({
    conversationId, sender: userId, receiver, text, messageType: 'text',
    replyTo: replyTo || null,
  });
  conv.lastMessage = msg._id.toString();
  conv.lastMessageAt = msg.createdAt;
  const entry = conv.unreadCount.find((u) => u.user === receiver);
  if (entry) entry.count += 1;
  else conv.unreadCount.push({ user: receiver, count: 1 });
  await conv.save();
  return toMessage(msg);
}
```

- [ ] **Step 4: Accept `reply_to` in the route** — in `flame/routes/conversations.js`, change `sendSchema` to:

```js
const sendSchema = z.object({
  text: z.string().min(1).max(2000),
  reply_to: objectId.optional(),
});
```

(`objectId` is already defined in the file.)

- [ ] **Step 5: Pass it through the controller** — in `flame/controllers/chatController.js`, change the `sendMessage` handler's service call to:

```js
  const data = await chatService.sendMessage(req.user.id, req.params.id, {
    text: req.body.text,
    replyTo: req.body.reply_to,
  });
```

- [ ] **Step 6: Run to verify pass**

Run: `node --test flame/__tests__/conversations.test.js`
Expected: PASS (all BE-1 tests + the 2 new reply tests).

- [ ] **Step 7: Commit** (confirm branch first)

```bash
cd /Users/firdavsmutalipov/Projects/BananaTalk/backend
git rev-parse --abbrev-ref HEAD   # feat/flame-chat
git add flame/services/chatService.js flame/routes/conversations.js flame/controllers/chatController.js flame/__tests__/conversations.test.js
git commit -m "feat(flame-chat): reply_to support on send"
```

---

### Task 2: Reactions

**Files (under `/Users/firdavsmutalipov/Projects/BananaTalk/backend/`):**
- Modify: `flame/services/chatService.js` (add `addReaction`, `removeReaction`, `_findMessage`; export them)
- Modify: `flame/controllers/chatController.js` (add handlers)
- Create: `flame/routes/messages.js`
- Modify: `flame/index.js` (register `/messages`)
- Test: `flame/__tests__/reactions.test.js`

**Interfaces:** `addReaction(userId, messageId, emoji)` / `removeReaction(userId, messageId)` — only the message's `sender` or `receiver` may react (else 403); missing message → 404; one reaction per user (add replaces the user's prior emoji). Endpoints: `POST /messages/:id/reactions` `{emoji}`, `DELETE /messages/:id/reactions`. Both return the updated message (snake_case) via `toMessage`.

- [ ] **Step 1: Write the failing test** — create `flame/__tests__/reactions.test.js` by COPYING the `setup()/teardown()/registerUser()/authH` harness from `flame/__tests__/conversations.test.js`, then EXTEND the `require.cache` bust list to also include `'../routes/messages'`. Add:

```js
async function openAndSend(app, a, b) {
  const conv = (await request(app).post('/flamebackend/v1/conversations')
    .set(authH(a.token)).send({ user_id: b.id }).expect(201)).body.data.id;
  const msg = await request(app).post(`/flamebackend/v1/conversations/${conv}/messages`)
    .set(authH(a.token)).send({ text: 'react to me' }).expect(201);
  return msg.body.data.id;
}

test('add, replace, and remove a reaction (one per user)', async (t) => {
  const app = await setup();
  t.after(teardown);
  const a = await registerUser(app, 'a@x.com');
  const b = await registerUser(app, 'b@x.com');
  const msgId = await openAndSend(app, a, b);

  // B reacts
  const r1 = await request(app).post(`/flamebackend/v1/messages/${msgId}/reactions`)
    .set(authH(b.token)).send({ emoji: '❤️' }).expect(201);
  assert.equal(r1.body.data.reactions.length, 1);
  assert.equal(r1.body.data.reactions[0].user_id, b.id);
  assert.equal(r1.body.data.reactions[0].emoji, '❤️');

  // B changes reaction → still one, replaced
  const r2 = await request(app).post(`/flamebackend/v1/messages/${msgId}/reactions`)
    .set(authH(b.token)).send({ emoji: '😂' }).expect(201);
  assert.equal(r2.body.data.reactions.length, 1);
  assert.equal(r2.body.data.reactions[0].emoji, '😂');

  // B removes
  const r3 = await request(app).delete(`/flamebackend/v1/messages/${msgId}/reactions`)
    .set(authH(b.token)).expect(200);
  assert.equal(r3.body.data.reactions.length, 0);
});

test('a non-participant cannot react (403)', async (t) => {
  const app = await setup();
  t.after(teardown);
  const a = await registerUser(app, 'a@x.com');
  const b = await registerUser(app, 'b@x.com');
  const c = await registerUser(app, 'c@x.com');
  const msgId = await openAndSend(app, a, b);
  await request(app).post(`/flamebackend/v1/messages/${msgId}/reactions`)
    .set(authH(c.token)).send({ emoji: '❤️' }).expect(403);
});

test('reacting to a missing message is 404', async (t) => {
  const app = await setup();
  t.after(teardown);
  const a = await registerUser(app, 'a@x.com');
  await request(app).post('/flamebackend/v1/messages/0123456789abcdef01234567/reactions')
    .set(authH(a.token)).send({ emoji: '❤️' }).expect(404);
});

test('reactions require auth (401)', async (t) => {
  const app = await setup();
  t.after(teardown);
  await request(app).post('/flamebackend/v1/messages/0123456789abcdef01234567/reactions')
    .send({ emoji: '❤️' }).expect(401);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test flame/__tests__/reactions.test.js`
Expected: FAIL — `/messages` route not mounted (404/401 mismatches; add returns 404 route-not-found).

- [ ] **Step 3: Add service methods** — in `flame/services/chatService.js`, add (before `module.exports`):

```js
async function _findMessage(messageId) {
  let m = null;
  try { m = await Message.findById(messageId); } catch (_) { m = null; }
  if (!m) throw new NotFoundError('message not found');
  return m;
}

function _assertMessageParticipant(m, userId) {
  if (m.sender !== userId && m.receiver !== userId) {
    throw new FlameError('FORBIDDEN', 'not your conversation', 403);
  }
}

async function addReaction(userId, messageId, emoji) {
  const m = await _findMessage(messageId);
  _assertMessageParticipant(m, userId);
  m.reactions = m.reactions.filter((r) => r.user !== userId);
  m.reactions.push({ user: userId, emoji });
  await m.save();
  return toMessage(m);
}

async function removeReaction(userId, messageId) {
  const m = await _findMessage(messageId);
  _assertMessageParticipant(m, userId);
  m.reactions = m.reactions.filter((r) => r.user !== userId);
  await m.save();
  return toMessage(m);
}
```

Then add `addReaction, removeReaction` to the `module.exports` object.

- [ ] **Step 4: Add controller handlers** — in `flame/controllers/chatController.js`, add and export:

```js
async function addReaction(req, res) {
  const data = await chatService.addReaction(req.user.id, req.params.id, req.body.emoji);
  res.status(201).json({ success: true, data });
}

async function removeReaction(req, res) {
  const data = await chatService.removeReaction(req.user.id, req.params.id);
  res.json({ success: true, data });
}
```

(Add both to `module.exports`.)

- [ ] **Step 5: Create the route** — `flame/routes/messages.js`:

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
const reactSchema = z.object({ emoji: z.string().min(1).max(16) });

router.post('/:id/reactions', auth, validate.params(idParam), validate.body(reactSchema), asyncHandler(ctrl.addReaction));
router.delete('/:id/reactions', auth, validate.params(idParam), asyncHandler(ctrl.removeReaction));

module.exports = router;
```

- [ ] **Step 6: Register the route** — in `flame/index.js`, add ONE line alongside the other
`router.use('/...', require('./routes/...'))` lines and BEFORE `router.use(errorMiddleware)`:

```js
router.use('/messages', require('./routes/messages'));
```

Read `flame/index.js` first and place it next to the existing `/conversations` registration; do not
reorder or touch other lines.

- [ ] **Step 7: Run to verify pass**

Run: `node --test flame/__tests__/reactions.test.js`
Expected: PASS (all 4 tests).

- [ ] **Step 8: Commit**

```bash
cd /Users/firdavsmutalipov/Projects/BananaTalk/backend
git rev-parse --abbrev-ref HEAD   # feat/flame-chat
git add flame/services/chatService.js flame/controllers/chatController.js flame/routes/messages.js flame/index.js flame/__tests__/reactions.test.js
git commit -m "feat(flame-chat): message reactions (add/replace/remove, participant-only)"
```

---

### Task 3: Full flame suite verification

**Files:** none.

- [ ] **Step 1:** Run `node --test flame/__tests__/*.test.js` from `/Users/firdavsmutalipov/Projects/BananaTalk/backend`.
Expected: PASS — all pre-existing + BE-1 + the new reply/reactions tests. No regressions.

- [ ] **Step 2:** `git -C /Users/firdavsmutalipov/Projects/BananaTalk/backend status --short` clean; `git -C … log --oneline c97a1cc..HEAD` shows the BE-1 + BE-2 commits on `feat/flame-chat`.

---

## Self-Review

**Spec coverage (Chat-BE-2):** reply_to on send → Task 1; reactions add/replace/remove → Task 2, both
endpoint-tested incl. auth (401), forbidden (403), not-found (404), validation (422). ✅

**Placeholder scan:** No TBD/TODO — full code for service/controller/route/register/tests. ✅

**Consistency:** `sendMessage({text, replyTo})` signature matches the controller's `replyTo: req.body.reply_to`
and the route's `reply_to` schema. Reaction participant check uses the same `FlameError('FORBIDDEN',...,403)`
as BE-1. `toMessage` (unchanged) already shapes `reactions:[{user_id,emoji}]` + `reply_to`, so the new
endpoints' responses are snake_case for free. New `/messages` route registered once, before `errorMiddleware`. ✅

**Safety:** all commits on `feat/flame-chat`, never `main`; branch re-checked each commit. ✅
