# Phase 1 — Chat Solidity (Realtime Layer Rebuild)

**Date:** 2026-05-08
**Status:** Draft, awaiting review
**Scope:** Rebuild the realtime chat layer end-to-end across the FastAPI backend (`flame_backend`) and the Flutter client (`flame`). Replace hand-rolled raw-WebSocket plumbing with a Socket.IO-based architecture modelled on the proven implementation in `language_exchange_backend_application/socket/socketHandler.js`, while keeping the dating-app backend's existing Redis pub/sub fan-out advantage and adding correctness guarantees the reference lacks (idempotency, persistent client outbox).

## Context

The existing chat layer is described by the user as "all not functional." A deep audit confirmed the diagnosis is correctness, not features: the feature surface (text/image/video/voice/sticker, typing, read receipts, message status, reactions, pins, mute) is all present in `app/chat/` and `lib/screens/chat/`, but the realtime plumbing has structural problems:

- Flutter `chat_screen.dart` mixes `setState` with Riverpod (rebuild storms; lines 31, 64, 86, 110)
- API client has `refreshToken()` but it is not auto-triggered on 401 (`lib/services/api_client.dart:273-296`)
- No client-side persistent outbox — any in-flight send during a network blip is lost
- No idempotency on the server — retries can duplicate
- No multi-device sync model — the reference handles up to 5 devices per user; the dating app has no cap or strategy
- WebSocket reconnection is a hand-rolled exponential backoff in `lib/services/websocket_service.dart:278-295`; the reference relies on Socket.IO's library-level reconnection
- Per-message `delivered/read` status field on the message document, instead of the simpler per-user `last_read_at` model used by the reference
- Minimal logging on the backend (mostly `print` statements in `app/core/redis.py`)
- Zero tests on either repo

This phase rebuilds the realtime layer to match the reference's robustness, fixes the listed bugs, lands the first real test foundation, and ships behind a feature flag so it can be killed without an app update if it regresses.

This is Phase 1 of a 4-phase sequence: **A (Chat solidity) → C (Production hardening) → B (Dating-loop polish) → D (UI overhaul)**. Phases 2–4 are out of scope here and have their own specs.

## Goals

1. The "send a message" path is correct under all of: flaky network, app backgrounded mid-send, app force-killed mid-send, two devices logged in, retry-after-server-error, token expiry mid-conversation.
2. The chat screen never drops into a "stuck" state requiring restart.
3. The chat layer is observable: every send produces one structured log line; key counters are scraped via `/metrics`.
4. The chat layer has tests that pass on a real Mongo + real Redis (no mocking the realtime layer).
5. Migration is non-destructive: the new code path lives behind `CHAT_V2_ENABLED` so the old path can stay alive for one release as a kill-switch.

## Non-goals (Phase 1)

- E2E encryption.
- Group chat (matches are 1:1).
- Message search.
- Server-side image resize / video transcoding (Phase 2).
- Push-notification redesign (Phase 2).
- New chat UI design (Phase 4).
- Voice/video calling.
- Reactions, pins, mute — already exist in REST and continue working unchanged.

## Architecture overview

### Backend (FastAPI)

**Add `python-socketio`** mounted on the existing FastAPI ASGI app. Delete the raw `websockets` handler in `app/chat/websocket.py` and the hand-rolled `app/core/redis.py` pub/sub wholesale. Use `socketio.AsyncRedisManager` with the same Redis instance — replaces the custom listener.

Mount path: `/ws/socket.io/` (Socket.IO default). Old `/ws` path is removed.

New module layout:

```
app/realtime/
  __init__.py
  server.py          # AsyncServer + Redis manager + ASGI mount
  auth.py            # JWT handshake validation, token-expiry monitoring
  handlers.py        # Event handlers
  rooms.py           # Room name helpers
  presence.py        # Online status + grace-period bookkeeping
  queue.py           # Offline message queue (Redis lists, 24h TTL)
  idempotency.py     # client_message_id dedup cache
  constants.py       # Event names, timeouts (single source of truth)
```

Existing REST endpoints in `app/chat/routes.py` stay, but their fan-out call sites swap to `await sio.emit(...)` instead of the custom `redis_pubsub.publish(...)`.

### Flutter client

**Add `socket_io_client: ^2.0.3+1`**, retire `web_socket_channel` and the current `lib/services/websocket_service.dart`.

New module layout:

```
lib/realtime/
  socket_client.dart        # Wraps socket_io_client; exposes SocketState
  event_handlers.dart       # Wires socket events into Riverpod providers
  outbox.dart               # Persistent send queue
  outbox_entry.dart         # Outbox entry model with status enum
  presence_tracker.dart     # Subscribes/unsubscribes presence by user_id
  constants.dart            # Mirrors backend event names
```

Reconnection delegated to the library (built-in, configurable backoff). Manual reconnect loop deleted.

### Deployment

- Sticky sessions are not required — Redis manager handles cross-worker fan-out.
- Dev: single uvicorn worker, local Redis. Prod: multi-worker, same Redis instance.
- No infra changes beyond what is already running.

### Environment configuration (dev vs prod)

Currently `lib/services/api_client.dart:7` hardcodes `https://flame.banatalk.com/v1`. Replace with build-flavor config:

```
lib/config/env.dart
  enum AppEnv { local, prod }
  class EnvConfig { final String apiBase; final String wsBase; }

  Local: apiBase = http://localhost:8000/v1
         wsBase  = ws://localhost:8000
  Prod:  apiBase = https://flame.banatalk.com/v1
         wsBase  = wss://flame.banatalk.com
```

Selection via Dart compile-time define `--dart-define=APP_ENV=local|prod`. Default is `prod` in release builds; debug builds default to `local` so `flutter run` "just works" against a local backend.

## Connection & auth lifecycle

### Handshake

Client connects with token in Socket.IO `auth: {token}` payload (not query string — token must not appear in access logs).

`app/realtime/auth.py` — `connect` handler:

1. Decode JWT (reuse `app/core/security.py:decode_access_token`).
2. Reject with `ConnectionRefusedError` if missing/expired/invalid. Anonymous sockets are never accepted.
3. Load minimal user doc (id, blocked_users, is_banned) into Redis cache `user:hot:{id}` with 60s TTL — hot path lookup, not a DB hit per message.
4. Register socket in user's room: `sio.enter_room(sid, f"user:{user_id}")`.
5. Track `(sid, device_id, connected_at)` in Redis hash `presence:sockets:{user_id}` for multi-device bookkeeping. `device_id` comes from a UUID generated once per install and stored in `SharedPreferences` on the client; passed in `auth: {token, device_id}`.
6. Emit `connection:ready` with `{user_id, sid, server_time}` so client can sync clock.

### Multi-device policy

- Cap: **3 concurrent sockets per user**. Reference uses 5; for a dating app 3 is plenty (phone + tablet/web + slack) and reduces fan-out cost.
- On 4th connection, oldest socket gets `force_disconnect` event with `reason: "superseded"` and is dropped.
- Sender's other devices receive `message:sent` mirror events so all devices stay in sync.

### Heartbeat

- Library-level: Socket.IO `ping_interval=25s`, `ping_timeout=60s`. Built-in.
- Application-level grace period: 10s after socket disconnects before marking user offline. Implemented as Redis key `presence:pending_offline:{user_id}` with 10s TTL; if user reconnects within 10s, key is deleted; if TTL expires, broadcast `presence:offline` to interested peers.

### Token expiry handling

- Access tokens are 60min (`ACCESS_TOKEN_EXPIRE_MINUTES`). Sockets often outlive that.
- On connect, server schedules an `asyncio` task at `exp - 120s` to emit `auth:token_expiring` to that specific sid.
- Client receives the event, calls `POST /auth/refresh` over REST, then emits `auth:token_refreshed` with the new token. Server validates, updates the socket's bound user state, no disconnect.
- If the client does not refresh in 120s, server emits `auth:token_expired` and disconnects with `reason: "token_expired"` so the client's reconnect loop fetches a fresh token first.

### Disconnect

Disconnect handler:

1. Remove sid from `presence:sockets:{user_id}`.
2. Clear all typing-timeout entries scoped to this sid.
3. If this was the user's last socket: schedule grace-period offline broadcast.
4. Drop hot-cache entry for this sid (user-level cache stays — other sockets may still need it).

## Message data flow & delivery semantics

### The canonical send flow

Client emits `message:send`:

```
{
  "client_message_id": "<uuid v4>",
  "conversation_id": "<id>",
  "type": "text|image|video|audio|voice|sticker",
  "content": "<text or sticker_id>",
  "reply_to_message_id": null,
  "media": { "url": "...", "width": 1080, "height": 1920, "duration_ms": 3200 }
}
```

Server handler `app/realtime/handlers.py:on_message_send`:

1. **Validate (sync, no I/O)**: required fields, type whitelist, content length cap (4000 chars), media schema if non-text.
2. **Idempotency check**: `GET idempotency:{user_id}:{client_message_id}` in Redis.
   - Hit → return cached canonical message id via ack. No duplicate persist, no duplicate broadcast.
   - Miss → continue.
3. **Authorization**: load conversation, verify user is a participant, verify peer has not blocked sender (hot-cache lookup).
4. **Persist to MongoDB**: insert into `messages`, server assigns `_id` and `server_timestamp`. Atomic single-doc write.
5. **Cache idempotency**: `SET idempotency:{user_id}:{client_message_id} = {message_id, server_timestamp} EX 86400`.
6. **Ack the sender immediately** with the canonical message dict (~50ms).
7. **Schedule async post-send work** (`asyncio.create_task`):
   - Update conversation's `last_message_id`, `last_message_at`, increment recipient's `unread_count`.
   - Enqueue push notification if recipient is offline.
   - Broadcast `message:new` to `room=user:{recipient_id}`.
   - Broadcast `message:sent` mirror to `room=user:{sender_id}`.
   - If recipient is offline → also append to `queue:offline:{recipient_id}` Redis list (TTL 24h, cap 50 messages).

### Why this order matters

- **Persist before broadcast** — receivers can never see a message that doesn't exist in the DB. No phantom messages on server restart.
- **Ack before broadcast** — sender perceives latency as persist time only.
- **Idempotency on `(user_id, client_message_id)`** — retries return the same canonical id; UI dedups by matching the id, never shows two copies.
- **Async post-send work** — slow push providers can't slow chat down.

### Delivery guarantees

- At-least-once from client → server, deduped by `client_message_id`.
- At-most-once from server → recipient socket. Missing messages recovered on next conversation open via REST `GET /conversations/{id}/messages?cursor=...`. Mongo is the source of truth.
- Order: not strict. Messages render sorted by `server_timestamp ASC` then `_id ASC` as tiebreaker.

### Read receipts (per-user `last_read_at` model)

Drop the existing per-message `delivered/read` status field. Adopt the reference's per-user pattern.

Schema additions on `Conversation`:
```
participants: [
  {
    user_id: ObjectId,
    last_read_message_id: ObjectId | null,
    last_read_at: datetime | null,
    unread_count: int,
    joined_at: datetime,
  }
]
```

Flow:
- Client emits `message:read` with `{conversation_id, last_read_message_id}` when chat screen scrolls past unread messages (debounced 500ms).
- Server: update that participant's `last_read_at` + `last_read_message_id`, set `unread_count = 0`, broadcast `read:update` to the *other* participant's room.
- Other participant's UI marks any message with `_id <= last_read_message_id` as "read."
- Unread badge = `unread_count` directly.

### Typing indicator

- Client emits `typing:start` with `{conversation_id}`. Coalesced — emit at most once per 3s.
- Server records `typing:{conversation_id}:{user_id}` in Redis with 5s TTL, broadcasts `typing:update` to peer. **TTL is the timeout** — no separate timer task.
- Client emits `typing:stop` on send, on chat close, or after 4s of no keystrokes.
- On disconnect: Lua script clears all `typing:*:{user_id}` keys for the disconnected user, broadcasts stops.

### Presence

- Two-state: `online` / `offline`.
- `last_seen_at` updated on disconnect.
- Client UI maps to: "Online", "Active 5m ago", "Active today", "Active this week", or hidden if >7d.
- Subscriptions: client emits `presence:subscribe` with `[user_ids]` (matches list). Server adds to interested-set in Redis. Status changes fan out only to subscribers.

## Media uploads

Currently the backend proxies multipart uploads through FastAPI → boto3 → Spaces. Switch to **presigned PUT URLs**.

1. Client calls `POST /media/presign` with `{type, mime, size_bytes, duration_ms?}`.
2. Server validates: max-size by type (image 10MB, video 50MB, audio 20MB, voice 5MB), allowed mime list. Returns `{upload_url, public_url, fields, expires_in: 300}`.
3. Client `PUT`s bytes directly to Spaces.
4. On success, client emits `message:send` with `media.url = public_url`.
5. Server validates the URL is from our bucket. (Phase 2 will add a HEAD check confirming the object exists.)

Existing `POST /chat/.../messages/image|video|audio|voice` endpoints are deprecated but kept alive for one release as a fallback. Removed in Phase 2.

### Voice messages

m4a, 64kbps mono, max 60s. Recorded with `record` (already in pubspec). Client measures duration locally and computes waveform peaks during recording — no server-side analysis.

### Stickers and GIFs

- Stickers: existing endpoints stay. Flutter integrates `lib/realtime/sticker_picker.dart` into the chat input bar. On select, emit `message:send` with `type: "sticker", content: sticker_id`. Server resolves sticker URL on receive — broadcast carries the URL.
- GIFs: integrate Tenor API (free tier). New backend endpoint `GET /media/gif/search?q=...&limit=20` proxies Tenor (rate-limit per user; no API key on client). Selected GIF sends as `type: "image"` with `media.url = tenor_cdn_url` — no re-upload to Spaces.

## Flutter client architecture

### Riverpod refactor

`chat_screen.dart` becomes a `ConsumerWidget` (or `ConsumerStatefulWidget` only for `TextEditingController` and `ScrollController`). All chat state moves into providers. Every existing `setState` call in the chat screen is removed.

### New provider graph

```
final messagesProvider = AsyncNotifierProvider.autoDispose
    .family<MessagesNotifier, List<Message>, String>(MessagesNotifier.new);

final outboxProvider = NotifierProvider<OutboxNotifier, List<OutboxEntry>>(
    OutboxNotifier.new);

final socketProvider = NotifierProvider<SocketNotifier, SocketState>(
    SocketNotifier.new);

final typingProvider = NotifierProvider.autoDispose
    .family<TypingNotifier, bool, String>(TypingNotifier.new);

final presenceProvider = NotifierProvider.family<PresenceNotifier, Presence, String>(
    PresenceNotifier.new);

final unreadProvider = Provider.family<int, String>(...);
```

### `OutboxNotifier`

Persistent send queue backed by `SharedPreferences` (Hive/Drift can come in later phase if needed).

Flow:
1. User taps send → message appended to outbox with `status: pending`, `client_message_id: uuid()`, `attempts: 0`.
2. UI immediately renders message in conversation with `pending` indicator.
3. If socket connected → emit `message:send`, set `status: sending`.
4. On ack → update with canonical `message_id` + `server_timestamp`, set `status: sent`, remove from outbox.
5. On ack-timeout (8s) or disconnect → keep `status: pending`, retry on reconnect. Max 5 attempts; after that mark `status: failed`, surface tap-to-retry affordance.

`outbox.flush()` runs on every `connection:ready`. Crash-safe: on cold start, anything still `pending`/`sending` is reset to `pending` and re-flushed once the socket connects. Server-side idempotency makes replay safe.

### `SocketNotifier`

States: `disconnected | connecting | connected | reconnecting | failed`.

- Wraps the `socket_io_client` instance, exposes events as a stream other notifiers subscribe to via `ref.listen`.
- Auto-connects on app launch after auth restored.
- Auto-disconnects on logout, **never on lifecycle changes** — backgrounding does not disconnect; the OS suspends the socket and the library reconnects on foreground.
- On `auth:token_expiring` event → calls `authProvider.refresh()`, then emits `auth:token_refreshed`.
- On `auth:token_expired` or 401 from REST → triggers full re-auth flow.

### Auto-refresh on 401

`api_client.dart` gets a request interceptor:

1. On any 401 from a non-refresh endpoint, pause the request, call `/auth/refresh` once (mutex-guarded — concurrent 401s share one refresh), retry the original.
2. If refresh itself returns 401 → emit `auth:logout`, clear tokens, `go_router` redirects to login.
3. The mutex prevents the storm where N simultaneous in-flight requests each kick off their own refresh.

### REST + socket harmony

REST is the source of truth on cold start:
- Open chat → fetch latest 50 messages via REST → `messagesProvider` initial state.
- Socket events thereafter merge into the same provider state.
- Same `client_message_id` dedup applies on the client.

### Files deleted in Phase 1

- `lib/services/websocket_service.dart` (replaced by `lib/realtime/socket_client.dart`).
- `lib/services/mock_data_service.dart` (audit confirmed it is unused).

## Error handling

Three failure tiers:

**Tier 1 — Recoverable per-request** (validation failure, conversation not found, blocked user, payload too large): reply via ack with `{ok: false, error: {code, message}}`. Codes mirror `app/core/exceptions.py` enum.

**Tier 2 — Infrastructure transient** (Mongo timeout, Redis blip): one immediate retry inside the handler with 200ms timeout. If retry fails, ack `{ok: false, error: {code: "TRANSIENT", retry_after_ms: 2000}}`. Client outbox respects `retry_after_ms`. Log at WARN with `event_id`, `user_id`, `client_message_id`.

**Tier 3 — Programming errors** (unhandled exception): caught by global socketio error handler. Log at ERROR with full traceback; ack `{ok: false, error: {code: "SERVER_ERROR"}}`. Never let an exception kill the connection.

### Client-side error UX

- Per-message: `pending` → `sending` → `sent` → `read`. `failed` shows red exclamation + tap-to-retry.
- Connection banner: small non-blocking strip at top of chat. "Reconnecting…" (yellow), "Offline" (red, after 30s of failed reconnects), nothing when connected. Self-dismissing.
- No modal dialogs, no toasts for transient issues.

## Observability

Backend switches to structured JSON logs. New `app/core/logging.py` module wrapping `python-json-logger`. Every line includes:

- `request_id` (or `socket_event_id` for socket handlers, generated per event)
- `user_id` (when authenticated)
- `conversation_id` (when applicable)
- `event` (e.g. `message.send.ok`, `message.send.idempotency_hit`, `socket.disconnect.grace_started`)
- `duration_ms` for any handler

Log volume target per chat send: 1 INFO line on success, 1 WARN on transient retry, 1 ERROR on failure.

Lightweight metrics via `prometheus_client`:
- `chat_messages_sent_total{type}`, `chat_acks_latency_seconds` (histogram)
- `chat_idempotency_hits_total`
- `socket_connections_active` (gauge by device-count buckets)
- `socket_disconnects_total{reason}`

Scrape endpoint at `/metrics`.

## Migration plan

Schema-additive, no destructive rewrites in Phase 1.

1. Add `participants: [{user_id, last_read_message_id, last_read_at, unread_count, joined_at}]` to `Conversation`.
2. One-shot script `scripts/migrate_chat_v2.py`:
   - For each existing `Conversation`, derive participants from `match_id`.
   - Compute `unread_count` per participant from current per-message `status` data.
   - Set `last_read_message_id` to the most recent message that participant marked read.
3. Old per-message `status` field stays in place; new code stops reading or writing it. Removed in a later cleanup pass.
4. `client_message_id` is forward-going only — no backfill.

## Rollout

- Feature-flag everything new with `CHAT_V2_ENABLED` env var on backend; build-time flag on Flutter.
- Backend: deploy with flag off → run migration script → flip flag → old WebSocket endpoint kept alive for one release → delete in Phase 2.
- Client: ship release with new code path, but able to fall back if `CHAT_V2_ENABLED=false` returned from a `/config` endpoint. Allows kill-switch without an app update.

## Testing strategy

This is the first real test foundation in either repo, scoped to chat.

### Backend (`tests/realtime/`)

`pytest-asyncio` + `socketio.AsyncSimpleClient` for in-process integration tests against a real Mongo (testcontainers) and real Redis (testcontainers).

Test cases:
- Happy path: send → ack → recipient gets `message:new` → recipient marks read → sender gets `read:update`.
- Idempotency: same `client_message_id` twice → same canonical id, one DB row, one broadcast.
- Offline delivery: recipient connects after sender → queue replays.
- Multi-device cap: 4th connection evicts oldest.
- Typing TTL: `typing:start` then no events → server auto-broadcasts `typing:stop` after 5s.
- Token refresh: `auth:token_expiring` → refresh → no disconnect.
- Blocked user: send to peer that blocked sender → `ok: false, code: BLOCKED`.

Target: ~20 tests covering happy path + each guarantee. Suite runs in <10s.

### Flutter

- `outbox_test.dart`: enqueue, ack, retry, max-attempts, persistence round-trip.
- `socket_client_test.dart`: state machine transitions with mocked socket.
- `messages_provider_test.dart`: pagination, optimistic insert, dedup on echo.

Target: ~15 tests. UI widget tests deferred to Phase 4.

## Done criteria

Phase 1 is shippable when:

1. All implementation behind `CHAT_V2_ENABLED`.
2. Backend test suite passes locally and in CI.
3. Flutter unit tests pass.
4. Manual QA matrix passes:
   - Airplane mode → send 3 messages → reconnect → all 3 deliver in order.
   - Force-quit during send → reopen → message either delivered exactly once or visibly failed.
   - Two devices logged in → message sent on phone appears on tablet within 1s.
   - Type long message, lock phone for 90s, unlock, send → goes through.
5. Idempotency load test: replay the same socket event 100x → exactly 1 message in DB, exactly 1 broadcast received.

## Open questions

None at this stage. Move to implementation plan.

## References

- Reference WebSocket implementation: `/Users/davis/Desktop/Personal/language_exchange_backend_application/socket/socketHandler.js`
- Backend audit findings: `app/auth/`, `app/chat/`, `app/community/service.py:208-335`, `app/core/redis.py`
- Client audit findings: `lib/services/websocket_service.dart`, `lib/screens/chat/chat_screen.dart`, `lib/services/api_client.dart:273-296`
