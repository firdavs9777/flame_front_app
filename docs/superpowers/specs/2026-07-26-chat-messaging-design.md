# Flame Chat / Messaging — Design Spec

> Date: 2026-07-26 · Spans two repos: the flame frontend (`~/Desktop/Flame/flame_front_app`)
> and the flame backend sub-app (`~/Projects/BananaTalk/backend/flame`).
> Modeled on BananaTalk's chat (`~/Projects/BananaTalk/backend` + `bananatalk_app`).

## 1. Goal

Make Flame's chat actually work. The chat **frontend already exists** (text bubbles, voice player,
stickers, attachments, translate UI, typing/read-receipt UI) but has **no backend** — `/matches`
and `/conversations` are empty stubs and there is no send/list endpoint. This feature builds a real
messaging backend in the flame sub-app and wires the UI to it, giving a BananaTalk-class **text
chat** core: list conversations, open a thread, send/receive, read receipts, reactions, reply/quote.

## 2. Scope decisions (approved 2026-07-26)

- **Build the flame chat backend** (not reuse BananaTalk's — flame has isolated users/JWT/Mongo).
- **REST-first**; Socket.IO realtime (typing/instant/presence) is a **follow-up**, not this build.
- **Text-first**; image/voice messages are **deferred** until the DigitalOcean Spaces upload fix
  (Phase 0) lands.
- A conversation can be **opened with any user** (created on first message), because real matching
  isn't live yet — so chat is usable now without waiting on the Swipe/match model.

## 3. Architecture

### Backend (flame sub-app, `/flamebackend/v1/*`, snake_case responses)

Follows the flame module pattern: `routes/*.js` → `controllers/*.js` → `services/*.js`, Mongoose
models on `getConn()` (the isolated `flameConn`), `middleware/auth.js` sets `req.user`, errors via
`utils/errors.js`, tests in `flame/__tests__/` (`node:test` + `supertest` + `mongodb-memory-server`).

**Models** (modeled on BananaTalk `Conversation`/`Message`, simplified for MVP):

- `Conversation`: `participants: [ObjectId ref User]` (exactly 2 for DMs), `last_message: ObjectId ref
  Message`, `last_message_at: Date`, `unread_count: [{ user: ObjectId, count: Number }]` (per-user),
  timestamps. A unique pair index prevents duplicate DMs between the same two users.
- `Message`: `conversation_id: ObjectId ref Conversation`, `sender: ObjectId ref User`, `receiver:
  ObjectId ref User`, `text: String (maxlength 2000)`, `message_type: enum ['text', ...]` (default
  'text'; media types reserved for later), `reactions: [{ user, emoji }]` (one per user), `reply_to:
  ObjectId ref Message` (nullable), `read: Boolean`, `read_at: Date`, `is_deleted: Boolean`,
  `deleted_for: [ObjectId]`, timestamps.

**REST endpoints:**

| Method | Path | Purpose | Round |
|---|---|---|---|
| `GET` | `/conversations` | List my conversations (other participant, last message, my unread count), paginated | BE-1 |
| `POST` | `/conversations` | Open/create a DM with `{ user_id }`; returns existing if present | BE-1 |
| `GET` | `/conversations/:id/messages?page&limit` | Thread messages, newest-page-first, paginated | BE-1 |
| `POST` | `/conversations/:id/messages` | Send `{ text }`; updates last_message + other user's unread | BE-1 |
| `PUT` | `/conversations/:id/read` | Mark the conversation + its messages read for me; zeroes my unread | BE-1 |
| `POST` | `/messages/:id/reactions` | Add/replace `{ emoji }` (one per user) | BE-2 |
| `DELETE` | `/messages/:id/reactions` | Remove my reaction | BE-2 |
| `POST` | `/conversations/:id/messages` (`reply_to`) | Reply is the same send endpoint with an optional `reply_to` message id | BE-2 |

Envelope: `{ success, data }` / `{ success, error:{code,message} }`; list endpoints include
`pagination`. Authorization: only a conversation's participants may read/write it (else `FORBIDDEN`).

### Frontend (this repo)

The chat services/providers already have the method shapes (`getConversations`, `getMessages`,
`sendMessage`, `markAsRead`); they just need real endpoints and correct optimistic behavior.

- **Wire** `chat_service` to the new endpoints (snake_case parsing).
- **Fix the data-losing send**: append an optimistic message immediately, reconcile with the server
  response, and on failure mark it failed + keep the text — never clear-then-error.
- **Re-enable the Chat tab** (revert the Phase 5 removal in `main_shell.dart`) once send/receive work.
- **Poll**: while a thread is open, poll `GET …/messages` every few seconds; refresh the conversation
  list on a slower interval. (Replaced by Socket.IO in the realtime follow-up.)
- **Features beyond plain text** (BananaTalk parity): read receipts, reactions, reply/quote — wired to
  BE-2.

## 4. Sequencing (each its own reviewed + tested plan)

1. **Chat-BE-1** — models + core REST (list, open, thread, send text, mark read) + backend tests.
2. **Chat-BE-2** — reactions + reply endpoints + tests.
3. **Chat-FE-1** — wire services to real endpoints, fix optimistic send, re-enable the Chat tab, polling.
4. **Chat-FE-2** — reactions + reply + read-receipt UI wiring.

Backend rounds land first so the frontend wires against real, tested endpoints. Each round is
independently shippable (BE endpoints are additive; FE-1 is what makes chat user-visible again).

## 5. Out of scope (deferred, tracked)

- **Socket.IO realtime**: typing indicators, instant delivery, presence/online. (The "realtime next"
  milestone — replaces polling.)
- **Media messages** (image/voice/video): depend on the Spaces upload fix (Phase 0).
- **The long tail** from BananaTalk: polls, corrections/vocab, TTS, forward, pin, disappearing/
  self-destruct, bookmarks, wallpaper/theme, saved phrases, search, drafts, daily limits.
- **Edit/delete** message: not in the initial four rounds; easy additive follow-up.

## 6. Risks & notes

- **Deploy → flame DB disconnect** (known gotcha #1): every backend deploy still needs
  `pm2 restart language`. The chat build adds routes but doesn't change this; fixing it is Phase 0.
- **Conversation creation without real matching**: opening a DM with any user is an MVP affordance;
  when the Swipe/match model ships, creation should be gated to matches. Keep the create path in one
  service method so that gate is a single change.
- **Casing**: new endpoints emit **snake_case** (flame convention for newer endpoints), which the
  frontend models already parse. Do not emit camelCase here.
- **Auth**: reuse the flame `middleware/auth.js` (flame JWT) for these routes — same token as the rest
  of the flame API.
