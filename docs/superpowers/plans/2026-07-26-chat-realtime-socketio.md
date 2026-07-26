# Chat Realtime (Socket.IO) — `/flame` Namespace

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Checkbox steps.

**Goal:** Add realtime chat (instant message delivery, typing, read) via a Socket.IO **`/flame` namespace**, with an **absolute constraint: zero effect on the BananaTalk main socket or the Fitbowl socket.**

## ISOLATION CONSTRAINTS (non-negotiable)

- flame realtime lives in its OWN namespace `io.of('/flame')`. It must NOT touch `initializeSocket` (BananaTalk root namespace) or `initializeFitBowlSocket` (`io.of('/fitbowl')`), nor any BananaTalk/Fitbowl model/route/controller.
- flame socket auth uses **`FLAME_JWT_SECRET`** via `flame/utils/jwt.js` `verifyAccess` — NOT `process.env.JWT_SECRET`. A BananaTalk/Fitbowl token cannot connect to `/flame`.
- The ONLY change to the shared `server.js` is **purely additive**: one `require` + one init call next to the existing `initializeFitBowlSocket(io)` line — **no existing line may be modified/removed/reordered** — and the init call MUST be wrapped in `try/catch` so a flame-socket failure can never crash the shared server or affect BananaTalk/Fitbowl.
- Everything else is NEW files under `flame/`.
- **Verification of isolation:** the full flame REST suite (`node --test flame/__tests__/*.test.js`) stays green, AND the `server.js` diff shows only additions (a reviewer confirms no BananaTalk/Fitbowl line changed).

## Architecture

- **`flame/socket/flameSocket.js`** (new): `initFlameSocket(io)` → `const ns = io.of('/flame')`; `ns.use()` auth middleware (`verifyAccess(socket.handshake.auth.token)` → join `flame_user_${userId}`); connection handler with `typing`/`stopTyping`/`markRead` client events that relay to the other participant's room; and exported emit helpers `emitNewMessage(io, receiverId, message)`, `emitRead(io, userId, conversationId)`.
- **`server.js`** (shared, additive only): `const { initFlameSocket } = require('./flame/socket/flameSocket');` + `try { initFlameSocket(io); } catch (e) { console.error('[flame] socket init failed (non-fatal):', e.message); }` right after `initializeFitBowlSocket(io);`.
- **Emit hook** in `flame/controllers/chatController.js`: after `sendMessage` returns the shaped message, `req.app.get('io')` → `emitNewMessage(io, data.receiver_id, data)` (guarded: only if io present). After `markRead`, optionally `emitRead`.
- **Frontend** (Chat-RT-FE): `socket_io_client` dep + `lib/services/flame_socket_service.dart` connecting to `wss://api.banatalk.com/flame` (and `ws://<local>/flame`) with the flame access token in `auth: {token}`; wire `chat_provider` to connect on thread open, append on `message:new`, show typing, emit typing/markRead; flip `EnvConfig.realtimeEnabled` on. Polling stays as fallback when the socket is disconnected.

## Tasks

### Task 1 (backend): `/flame` namespace handler + isolated server.js init + emit hook

**Files:** Create `flame/socket/flameSocket.js`; modify `server.js` (additive only); modify `flame/controllers/chatController.js` (emit hook).

- [ ] **Step 1:** Create `flame/socket/flameSocket.js` mirroring `socket/fitbowlHandler.js` but using flame auth:

```js
const { verifyAccess } = require('../utils/jwt');

const NS = '/flame';
const room = (userId) => `flame_user_${userId}`;

function initFlameSocket(io) {
  const ns = io.of(NS);

  ns.use((socket, next) => {
    try {
      const token = socket.handshake.auth && socket.handshake.auth.token;
      if (!token) return next(new Error('Authentication required'));
      const payload = verifyAccess(token); // flame JWT (FLAME_JWT_SECRET)
      socket.userId = payload.userId;
      return next();
    } catch (err) {
      return next(new Error('Authentication failed'));
    }
  });

  ns.on('connection', (socket) => {
    const userId = socket.userId;
    socket.join(room(userId));

    // Relay typing to the other participant.
    socket.on('typing', (data) => {
      if (data && data.to) ns.to(room(data.to)).emit('typing', { from: userId, conversation_id: data.conversation_id });
    });
    socket.on('stopTyping', (data) => {
      if (data && data.to) ns.to(room(data.to)).emit('stopTyping', { from: userId, conversation_id: data.conversation_id });
    });
    // Relay read to the other participant.
    socket.on('markRead', (data) => {
      if (data && data.to) ns.to(room(data.to)).emit('read', { by: userId, conversation_id: data.conversation_id });
    });

    socket.on('disconnect', () => {});
  });

  return ns;
}

// Emit a newly-sent message to its receiver's room.
function emitNewMessage(io, receiverId, message) {
  if (!io || !receiverId) return;
  io.of(NS).to(room(receiverId)).emit('message:new', message);
}

function emitRead(io, userId, conversationId) {
  if (!io || !userId) return;
  io.of(NS).to(room(userId)).emit('read', { conversation_id: conversationId });
}

module.exports = { initFlameSocket, emitNewMessage, emitRead };
```

- [ ] **Step 2:** In `server.js`, ADD (do not modify any existing line) — a require near the other socket requires, and right AFTER the existing `initializeFitBowlSocket(io);` line:

```js
const { initFlameSocket } = require('./flame/socket/flameSocket');
```
```js
try { initFlameSocket(io); } catch (e) { console.error('[flame] socket init failed (non-fatal):', e.message); }
```

Read `server.js` first; confirm the additions are purely additive and the `initializeSocket(io)` / `initializeFitBowlSocket(io)` calls are untouched.

- [ ] **Step 3:** In `flame/controllers/chatController.js` `sendMessage`, after getting `data` from the service, emit to the receiver (guarded, non-fatal):

```js
async function sendMessage(req, res) {
  const data = await chatService.sendMessage(req.user.id, req.params.id, {
    text: req.body.text,
    replyTo: req.body.reply_to,
  });
  try {
    const io = req.app.get('io');
    if (io) require('../socket/flameSocket').emitNewMessage(io, data.receiver_id, data);
  } catch (_) { /* realtime is best-effort; never fail the REST send */ }
  res.status(201).json({ success: true, data });
}
```

- [ ] **Step 4 (verify isolation + no regression):**
  - `node --test flame/__tests__/*.test.js` → all green (REST unaffected by the namespace).
  - `node -e "require('./flame/socket/flameSocket')"` loads without error.
  - `node --check server.js` (syntax OK).
  - Confirm `git diff server.js` shows ONLY additions (no BananaTalk/Fitbowl line changed).
- [ ] **Step 5:** Commit (branch `feat/flame-chat`): `feat(flame-chat): realtime via isolated /flame Socket.IO namespace`.

> No socket unit test: `socket.io-client` is not installed in the backend, so the handler is verified structurally + by the REST suite staying green + review. The `/flame` namespace + flame-JWT auth + additive try/catch server.js init guarantee zero effect on BananaTalk/Fitbowl.

### Task 2 (frontend): flame socket client + provider wiring

**Files:** `pubspec.yaml` (+`socket_io_client`), `lib/services/flame_socket_service.dart` (new), `lib/providers/chat_provider.dart`, `lib/config/env.dart` (flip `realtimeEnabled` for local; keep prod off until backend deploys), test for the service seam where feasible.

- [ ] Add `socket_io_client`; create a `FlameSocketService` (connect to `<wsBase>/flame` with `auth:{token}`, expose streams for `message:new`/`typing`/`read`, and `emitTyping/emitMarkRead`). Wire `chat_provider` to connect on thread open, append incoming `message:new` (de-dupe by id), reflect typing, and emit typing/markRead; keep polling as a fallback when disconnected. Gate on a realtime flag. Analyze clean + full `flutter test` green. Commit.

(Task 2 is scoped/executed after Task 1 review — the frontend socket wiring.)

## Self-Review
Isolation constraints are explicit and verified (separate namespace, separate secret, additive+try/catch server.js, REST suite green, diff review). Backend Task 1 is structurally-verified (no socket client for tests). Frontend Task 2 follows. ✅
