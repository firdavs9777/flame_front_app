# Chat-A Backend — Edit/Delete + Presence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Checkbox steps.

**Goal:** Backend for sub-project A: message **edit/delete** endpoints (with emits) and **online presence** on the isolated `/flame` Socket.IO namespace.

## Global Constraints

- Repo `/Users/firdavsmutalipov/Projects/BananaTalk/backend`, branch **`feat/flame-chat`** (never `main`). Re-check branch before each commit.
- ISOLATION still absolute: presence/emit code stays on `io.of('/flame')`; zero effect on BananaTalk/Fitbowl sockets.
- Flame conventions: String ids; snake_case responses; `FlameError`/`NotFoundError`/`ValidationError` (no ForbiddenError → `new FlameError('FORBIDDEN', msg, 403)`); models via `getConn().model`; zod route validation; tests `node --test flame/__tests__/*.test.js` (each test spins its own in-memory Mongo — slow, be patient, don't background).
- Reference (read first): `flame/services/chatService.js`, `flame/controllers/chatController.js`, `flame/routes/messages.js` + `conversations.js`, `flame/socket/flameSocket.js`, `flame/models/{Message,Conversation}.js`, `flame/__tests__/{conversations,reactions}.test.js`.

---

### Task 1: Edit + delete messages (service + endpoints + emits + tests)

**Files:** modify `flame/services/chatService.js`, `flame/controllers/chatController.js`, `flame/routes/messages.js`, `flame/socket/flameSocket.js`; test `flame/__tests__/message_edit_delete.test.js` (create, mirror conversations.test.js harness).

**Service (`chatService.js`):**
- Extend `toMessage` to include `is_edited: m.isEdited || false`, `edited_at: m.editedAt?.toISOString() || null`, `is_deleted: m.isDeleted || false` (Message model already has isEdited/editedAt?/isDeleted; if `editedAt` field is missing on the schema, add it: `editedAt: {type: Date, default: null}`).
- `editMessage(userId, messageId, text)`: load message (`_findMessage`); `if (m.sender !== userId) FORBIDDEN 403`; `if (m.isDeleted) ValidationError`; `if (Date.now() - m.createdAt > 15*60*1000)` → `new FlameError('EDIT_WINDOW_EXPIRED','edit window passed',422)`; set `m.text=text; m.isEdited=true; m.editedAt=new Date()`; save; return `toMessage(m)`.
- `deleteMessage(userId, messageId, scope)`: load message; `_assertMessageParticipant` (sender or receiver). If `scope==='everyone'`: `if (m.sender !== userId) FORBIDDEN`; `if (Date.now()-m.createdAt > 60*60*1000)` → `FlameError('DELETE_WINDOW_EXPIRED',…,422)`; set `m.isDeleted=true; m.text=''`; save; return `{message: toMessage(m), scope:'everyone', receiver_id: m.receiver === userId ? m.sender : m.receiver}`. If `scope==='me'` (default): push userId into `m.deletedFor` (dedupe); save; return `{message: toMessage(m), scope:'me'}`.
- Export both. (Note: `getMessages` should also exclude messages where `deletedFor` includes the caller — add `deletedFor: { $ne: userId }` to its filter so for-me deletes hide.)

**Socket (`flameSocket.js`):** add `emitMessageEdited(io, receiverId, message)` and `emitMessageDeleted(io, receiverId, message)` mirroring `emitNewMessage` (emit `message:edited` / `message:deleted` to `flame_user_<receiverId>`). Export them.

**Controller (`chatController.js`):**
- `editMessage(req,res)`: `data = await chatService.editMessage(req.user.id, req.params.id, req.body.text)`; guarded emit `emitMessageEdited(io, <the other participant of data>, data)`; `res.json({success:true,data})`. (Determine the other participant: `data.sender_id===req.user.id ? data.receiver_id : data.sender_id`.)
- `deleteMessage(req,res)`: `result = await chatService.deleteMessage(req.user.id, req.params.id, req.query.scope || 'me')`; if `result.scope==='everyone'` guarded emit `emitMessageDeleted(io, result.receiver_id, result.message)`; `res.json({success:true, data: result.message})`.

**Routes (`routes/messages.js`):** add
`router.patch('/:id', auth, validate.params(idParam), validate.body(z.object({text: z.string().min(1).max(2000)})), asyncHandler(ctrl.editMessage));`
`router.delete('/:id', auth, validate.params(idParam), validate.query(z.object({scope: z.enum(['me','everyone']).optional()})), asyncHandler(ctrl.deleteMessage));`
(Confirm `validate.query` exists; if not, read scope in the controller with a default and skip query validation.)

**Tests (`message_edit_delete.test.js`):** copy the conversations.test.js harness. Cover: edit own message → is_edited true + text changed + 401/403 (other user)/422 (after faking an old createdAt is hard — instead test the happy path + non-sender 403 + editing a deleted message fails); delete-for-everyone by sender → is_deleted true, text empty; delete-for-everyone by non-sender → 403; delete-for-me → message hidden from that user's `getMessages` thread but still visible to the other. (For time-window tests: optionally insert a Message with an old createdAt directly via the model to assert the 422 expiry.)

Steps: write failing tests → run fail → implement service+socket+controller+routes → run pass → `node --test flame/__tests__/conversations.test.js flame/__tests__/reactions.test.js` (no regression) → commit `feat(flame-chat): edit + delete messages with socket emits`. Confirm branch feat/flame-chat.

---

### Task 2: Online presence (presenceService + socket wiring + tests)

**Files:** create `flame/services/presenceService.js`; modify `flame/socket/flameSocket.js`; modify `flame/services/chatService.js` (a helper to list a user's conversation-partner ids); test `flame/__tests__/presence.test.js` (create).

**presenceService.js (pure, unit-testable — no socket):**
- An in-memory `Map<userId, count>`. Functions: `markOnline(userId) → boolean nowOnline` (count 0→1 returns true), `markOffline(userId) → boolean nowOffline` (count→0 returns true), `isOnline(userId)`, `onlineAmong(userIds) → string[]`. Keep it a plain module with an internal map + a `reset()` for tests.

**chatService.js:** add `partnerIdsOf(userId) → Promise<string[]>` — the other participant of each of the user's Conversations (distinct). Export it.

**flameSocket.js wiring:**
- On connection (after join): `const partners = await chatService.partnerIdsOf(userId)`. `const wasOffline = presenceService.markOnline(userId)`. Load the connecting user's `showOnlineStatus` (via `User.findById(userId).lean()`); if true AND wasOffline, emit `presence {user_id:userId, online:true}` to each `flame_user_<partnerId>`. Send the connecting socket a `presence:bulk {online:[...]}` = partners currently online whose OWN showOnlineStatus is true (look those up; keep it simple — filter `presenceService.onlineAmong(partners)` then filter by each partner's setting).
- On disconnect: `const nowOffline = presenceService.markOffline(userId)`; if nowOffline AND the user's showOnlineStatus, emit `presence {user_id:userId, online:false}` to partner rooms. (Recompute partners on disconnect or cache them on the socket at connect — cache on `socket.partnerIds`.)
- Wrap presence lookups in try/catch (never crash the socket). Keep it `/flame`-only.

**Tests (`presence.test.js`):** unit-test presenceService (markOnline true only on 0→1; markOffline true only on →0; multiple connections; onlineAmong filters correctly; reset). The socket wiring itself is structurally reviewed (no socket client in harness).

Steps: write failing presenceService test → implement presenceService → pass → wire flameSocket + partnerIdsOf (structural) → `node --check` the socket file + `node -e require` it → run the full flame suite (no regression) → commit `feat(flame-chat): online presence on /flame (partners-only, respects showOnlineStatus)`. Confirm branch.

---

### Task 3: Full flame suite verification
- `node --test flame/__tests__/*.test.js` all green; branch `feat/flame-chat`; working tree clean.

## Self-Review
Edit/delete: authorization (sender-only for edit + delete-everyone), time windows, for-me vs for-everyone, emits — covered + tested. Presence: pure service unit-tested; socket wiring isolated on /flame, respects showOnlineStatus, partners-only. Isolation preserved. Snake_case + String ids throughout. ✅
