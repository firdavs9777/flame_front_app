# Phase 1 — Chat Solidity (Realtime Layer Rebuild)

**Date:** 2026-05-08
**Status:** Draft, awaiting review
**Revision:** 2 (addresses spec-review iteration 1)
**Scope:** Rebuild the realtime chat layer end-to-end across the FastAPI backend (`flame_backend`) and the Flutter client (`flame`). Replace hand-rolled raw-WebSocket plumbing with a Socket.IO-based architecture modelled on the proven implementation in `language_exchange_backend_application/socket/socketHandler.js`, while keeping the dating-app backend's existing Redis pub/sub fan-out advantage and adding correctness guarantees the reference lacks (idempotency, persistent client outbox).

## Context

The existing chat layer is described by the user as "all not functional." A deep audit confirmed the diagnosis is correctness, not features: the feature surface (text/image/video/voice/sticker, typing, read receipts, message status, reactions, pins, mute) is all present in `app/chat/` and `lib/screens/chat/`, but the realtime plumbing has structural problems:

- Flutter `chat_screen.dart` mixes `setState` with Riverpod (rebuild storms; lines 31, 64, 86, 110)
- API client has `refreshAccessToken()` but it is not auto-triggered on 401 (`lib/services/api_client.dart:273-296`)
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

## Versions and pins

Hard pins to lock in this phase:

- **Backend** (add to `requirements.txt`):
  - `python-socketio[asyncio]>=5.11.2,<6.0.0`
  - `python-engineio>=4.9.0,<5.0.0`
  - `prometheus-client>=0.20.0,<0.22.0`
  - `python-json-logger>=2.0.7,<3.0.0`
  - Existing `fastapi==0.109.0`, `motor==3.6.0`, `beanie==1.26.0`, `redis==5.0.1` are compatible.
- **Flutter** (add to `pubspec.yaml`):
  - `socket_io_client: ^2.0.3+1` (Socket.IO protocol v5 / Engine.IO v4 — matches the server pin)
  - Dart SDK `^3.10.7` already in pubspec is compatible.
- **Server-side Socket.IO mount path:** `/ws/socket.io/`. Flutter client must explicitly configure `path: '/ws/socket.io'` (the library default is `/socket.io`).

## Architecture overview

### Backend (FastAPI)

**Add `python-socketio`** mounted on the existing FastAPI ASGI app. Use `socketio.AsyncRedisManager` against the same Redis instance — replaces the custom `redis_pubsub.publish/subscribe` flow.

**Scope of code removal — narrowed.** The reviewer flagged the previous version's "delete `app/core/redis.py` wholesale" wording as overbroad. Corrected scope:

- `app/chat/websocket.py` — entire file deleted; routes/handlers/notify_* migrated as below.
- `app/core/redis.py` — the **pub/sub class** (`RedisPubSub`) and its singleton `redis_pubsub` are deleted; the file itself stays as a thin connection-pool helper if anything else imports it.
- `app/core/cache.py` — **untouched**. Independent caching layer.
- `notify_*` helpers — relocated, not deleted. Migration table:

  | Old `app/chat/websocket.py` helper | New location | New emit target |
  | --- | --- | --- |
  | `notify_new_message` | `app/realtime/emitters.py` | `sio.emit("message:new", ..., room=f"user:{recipient_id}")` |
  | `notify_message_edited` | same | `sio.emit("message:edited", ..., room=f"user:{recipient_id}")` |
  | `notify_message_deleted` | same | `sio.emit("message:deleted", ..., room=f"user:{recipient_id}")` |
  | `notify_reaction_added/removed` | same | `sio.emit("reaction:update", ..., room=f"user:{recipient_id}")` |
  | `notify_message_pinned/unpinned` | same | `sio.emit("pin:update", ..., room=f"user:{recipient_id}")` |
  | `notify_new_match` (used outside chat) | same | `sio.emit("match:new", match_data, room=f"user:{user_id}")` |
  | `notify_user_online` | replaced by presence module | per-subscriber `presence:update` |

  All call sites in `app/community/service.py`, `app/chat/routes.py`, `app/chat/service.py` etc. are updated to import from `app/realtime/emitters.py`. **Reactions, pins, mute, edit, delete are explicitly in Phase 1 scope** because their old code path goes away — they must be ported, not deferred.

Mount path: `/ws/socket.io/`. Old `/ws` path (defined in current `app/chat/websocket.py`) is removed.

New module layout:

```
app/realtime/
  __init__.py
  server.py          # AsyncServer + Redis manager + ASGI mount
  auth.py            # JWT handshake validation, token-expiry monitoring
  handlers.py        # Event handlers
  emitters.py        # Server-to-client emit helpers (replaces notify_*)
  rooms.py           # Room name helpers
  presence.py        # Online status + grace-period bookkeeping + reaper
  queue.py           # Offline message queue (Redis lists, 24h TTL)
  idempotency.py     # client_message_id dedup cache
  constants.py       # Event names, timeouts (single source of truth)
```

Existing REST endpoints in `app/chat/routes.py` stay, but their `notify_*` call sites point to the new emitters.

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
         wsBase  = ws://localhost:8000   (Socket.IO path appended by client config)
  Prod:  apiBase = https://flame.banatalk.com/v1
         wsBase  = wss://flame.banatalk.com
```

Selection via Dart compile-time define `--dart-define=APP_ENV=local|prod`. Default is `prod` in release builds; debug builds default to `local` so `flutter run` works against a local backend immediately.

## Connection & auth lifecycle

### Handshake

Client connects with token in Socket.IO `auth: {token, device_id}` payload (not query string — token must not appear in access logs).

`app/realtime/auth.py` — `connect` handler:

1. Decode JWT (reuse `app/core/security.py:decode_access_token`).
2. Reject with `ConnectionRefusedError` if missing/expired/invalid. Reject if `device_id` is missing or longer than 64 chars. Anonymous sockets are never accepted.
3. Load minimal user doc (id, blocked_users, is_banned) into Redis cache `user:hot:{id}` with 60s TTL — hot path lookup, not a DB hit per message.
4. Register socket in user's room: `sio.enter_room(sid, f"user:{user_id}")`.
5. Multi-device cap (3): enforced via Redis sorted-set `presence:sids:{user_id}` keyed by `connected_at` score. On connect, `ZADD` then `ZCARD`. If count > 3, `ZRANGE` lowest score, force-disconnect that sid.
6. Emit `connection:ready` with `{user_id, sid, server_time}` so client can sync clock.

### Multi-device policy & sid bookkeeping (correctness fix)

Reviewer flagged that Redis hashes have no per-field TTL and orphaned sids would block legitimate connections.

Implementation:
- Use Redis sorted-set `presence:sids:{user_id}` with `score = connected_at_unix`, `member = sid`.
- On connect: `ZADD`. On disconnect: `ZREM`.
- **Reaper task** runs every 60s in a single worker (chosen by `socketio.Manager.is_leader()`-style election via Redis `SET NX EX`): for each user with non-empty sorted set, scan members not present in `sio.manager.rooms.get("/", f"user:{user_id}")`. Any sid not in the live room set whose score is older than `ping_timeout + 30s` is removed.
- Source of truth for "is sid alive?" is `sio.manager` itself; the sorted-set is a Redis-side bookkeeping cache.

Cap: **3 concurrent sockets per user**. On 4th connection, oldest gets `force_disconnect` event with `reason: "superseded"` and is dropped.

Sender's other devices receive `message:sent` mirror events so all devices stay in sync (see "Mirror echo handling" below).

### Heartbeat

- Library-level: Socket.IO `ping_interval=25s`, `ping_timeout=60s`.
- Application-level grace period: 10s after socket disconnects before marking user offline. Implemented as Redis key `presence:pending_offline:{user_id}` with 10s TTL; if user reconnects within 10s, key is deleted; if TTL expires (detected by keyspace notifications subscribed in `presence.py`), broadcast `presence:offline` to interested peers.
- Fallback if keyspace notifications are not enabled in Redis: in-process `asyncio.sleep(10)` task per disconnect, with cancellation on reconnect. Spec mandates **keyspace notifications enabled** (`notify-keyspace-events Ex`); the in-process fallback is documented but discouraged.

### Token expiry handling (timer cancellation fix)

- Access tokens are 60min (`ACCESS_TOKEN_EXPIRE_MINUTES`). Sockets often outlive that.
- On connect, server schedules an `asyncio` task at `exp - 120s` to emit `auth:token_expiring` to the specific sid. Task handle is stored on the socket session: `await sio.save_session(sid, {"token_expiry_task": task})`.
- Client receives the event, calls `POST /auth/refresh` over REST, then emits `auth:token_refreshed` with the new token.
- On `auth:token_refreshed`: server validates the new token, **cancels the existing scheduled task** (`task.cancel()`), schedules a new one at the new `exp - 120s`, updates the session.
- If the client does not refresh within 120s, the original scheduled task fires `auth:token_expired` and disconnects with `reason: "token_expired"`.

### Banned user enforcement (correctness fix)

Reviewer correctly flagged that 60s hot-cache TTL only enforces on the user's *next outbound* event.

Implementation:
- New Redis pub/sub channel `user:banned` (separate from chat fan-out).
- When admin sets `is_banned=true`, the auth/admin code also `await sio.emit_to_namespace_publish("user:banned", {"user_id": ...})` (or a direct Redis `PUBLISH`).
- `app/realtime/server.py` subscribes on startup; on message, iterates `presence:sids:{user_id}` and force-disconnects each sid with `reason: "banned"` regardless of whether the user is currently sending events.
- Hot-cache 60s TTL still applies to the per-event `is_banned` check so cold-cache cases also catch bans.

### Disconnect

Disconnect handler:

1. `ZREM presence:sids:{user_id} sid`.
2. Clear typing keys for this user (see Typing section).
3. If this was the user's last socket: set `presence:pending_offline:{user_id}` with 10s TTL; on TTL expiry, broadcast offline.
4. Drop hot-cache entry only if no other sids remain.

## Message data flow & delivery semantics

### The canonical send flow

Client emits `message:send`:

```
{
  "client_message_id": "<uuid v4, max 64 chars>",
  "conversation_id": "<id>",
  "type": "text|image|video|audio|voice|sticker|gif",
  "content": "<text or sticker_id>",
  "reply_to_message_id": null,
  "media": { "url": "...", "width": 1080, "height": 1920, "duration_ms": 3200 }
}
```

Server handler `app/realtime/handlers.py:on_message_send`:

1. **Validate (sync, no I/O)**: required fields, type whitelist (`gif` and `sticker` use existing `MessageType` enum — add `MessageType.GIF` to `app/models/message.py` if not present), content length cap (4000 chars), `client_message_id` length cap (64 chars), media schema if non-text, media URL must match `^https://(my-projects-media\.sfo3\.cdn\.digitaloceanspaces\.com|media\.tenor\.com)/...`.
2. **Idempotency check**: `GET idempotency:{user_id}:{client_message_id}` in Redis.
   - Hit → ack with cached canonical message dict. No duplicate persist, no duplicate broadcast.
   - Miss → continue.
3. **Authorization**: load conversation, verify user is `user1_id` or `user2_id`, verify peer has not blocked sender (hot-cache lookup).
4. **Persist to MongoDB**: insert into `messages`, server assigns `_id` and `server_timestamp`. Atomic single-doc write.
5. **Cache idempotency**: `SET idempotency:{user_id}:{client_message_id} = {message_id, server_timestamp_iso} EX 86400`.
6. **Ack the sender immediately** with the canonical message dict (~50ms target).
7. **Schedule async post-send work** (`asyncio.create_task`):
   - Update conversation's `last_message_*`, `$inc` recipient's unread counter (using existing per-user fields during transition — see Migration plan).
   - Enqueue push notification if recipient is offline (see "Push notification failure handling").
   - Broadcast `message:new` to `room=f"user:{recipient_id}"`.
   - Broadcast `message:sent` mirror to `room=f"user:{sender_id}"` with `skip_sid=originating_sid` so the originating client does not receive its own mirror echo.
   - If recipient is offline → also append to `queue:offline:{recipient_id}` Redis list (TTL 24h, cap 50 messages, FIFO via `LPUSH` + `LTRIM 0 49`).

### Mirror echo handling

The `message:sent` mirror is emitted with `skip_sid=originating_sid`. The originating sid received its ack in step 6; it does not need the mirror. Other sids of the same user receive the mirror and merge into `messagesProvider`, deduping by `client_message_id` if they already saw the original via shared state (they will not, because the original ack only goes to the originating sid).

### Push-notification failure handling

`app/realtime/emitters.py:enqueue_push` calls the existing FCM/APNs subsystem. Failure handling:
- 4xx (invalid token, including 410) → log at INFO, mark device token stale in DB, do not retry.
- 5xx / network → log at WARN, do not retry inline (handled by FCM's own retry behavior).
- **Push failures never fail the chat send** — the message is already persisted and broadcast.

### Delivery guarantees

- At-least-once from client → server, deduped by `client_message_id`.
- At-most-once from server → recipient socket. Missing messages recovered on next conversation open via REST `GET /conversations/{id}/messages?cursor=...`. Mongo is the source of truth.
- Order: not strict. Messages render sorted by `server_timestamp ASC` then `_id ASC` as tiebreaker.

### Read receipts (per-user `last_read_at` model with monotonic write)

Drop the per-message `delivered/read` status field for read-state purposes. Keep the existing field in the model but stop reading or writing it from new code (see Migration plan).

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

`participants[]` is **dual-written alongside** existing `user1_id`/`user2_id`/`user1_unread_count`/`user2_unread_count` for the entire transition window (one release). Existing helpers `get_other_user_id`, `get_unread_count`, `increment_unread`, `reset_unread` are kept; they internally update the participant record too. This avoids a flag-day cutover.

Flow:
- Client emits `message:read` with `{conversation_id, last_read_message_id}` when chat screen scrolls past unread messages (debounced 500ms).
- Server: monotonic conditional write — only update if `_id > current last_read_message_id`. Use Mongo `$max` on `last_read_at` plus filter clause `participants.last_read_message_id < new_id`. Set `unread_count = 0`. Broadcast `read:update` to peer.
- Other participant's UI marks any message with `_id <= last_read_message_id` as "read."
- Unread badge = `unread_count` directly.

### Typing indicator

- Client emits `typing:start` with `{conversation_id}`. Coalesced — emit at most once per 2s.
- Server records `typing:{conversation_id}:{user_id}` in Redis with 4s TTL. Broadcasts `typing:update` `{is_typing: true}` to peer (use `room=f"user:{peer_id}"`).
- Client emits `typing:stop` on send, on chat close, or after 3s of no keystrokes.
- **Disconnect cleanup (correctness fix):** the previous spec's "Lua script clears all typing keys" was not implementable without `SCAN`. Replace with a secondary index: maintain Redis SET `typing_index:{user_id}` containing the keys the user currently holds (`SADD` on typing:start, `SREM` on typing:stop or on TTL expiry via keyspace notification). On disconnect, read members of `typing_index:{user_id}`, `DEL` each plus the SET itself, broadcast `typing:update` `{is_typing: false}` to each conversation peer.
- If keyspace notifications are not enabled and the SET drifts (entry whose underlying key already expired), the cleanup `DEL` is a no-op; harmless.

### Presence

- Two-state: `online` / `offline`.
- Backend stops writing `User.is_online` directly. The field stays in the schema for compatibility but is updated by a **background sync task every 60s** that reads `presence:sids:*` and computes online users — this exists only to keep historical reports working. Realtime presence is Redis-only.
- `User.last_active` (already in schema) is updated on disconnect for "last seen" UX.
- Subscriptions: client emits `presence:subscribe` with `[user_ids]` (matches list). Server adds to interested-set in Redis. Status changes fan out only to subscribers.

## Media uploads (security and correctness fixes)

Currently the backend proxies multipart uploads through FastAPI → boto3 → Spaces. Switch to **presigned PUT URLs** with these constraints:

1. Client calls `POST /media/presign` with `{type: "image|video|audio|voice", mime, size_bytes, duration_ms?}`.
2. Server validates: max-size by type (image 10MB, video 50MB, audio 20MB, voice 5MB), allowed mime list.
3. **Server generates the object key** — client cannot specify it. Format: `flame_backend/{category}/{user_id}/{uuid4}.{ext}`. This prevents one user from overwriting another user's objects.
4. Server signs a PUT URL with `boto3.client.generate_presigned_url('put_object', ...)`. Signed headers: `Content-Type`, `Content-Length`, `x-amz-acl=public-read`. Expires in 300s.
5. Response: `{upload_url, public_url, required_headers: {...}}`. **Drop `fields` from the response** (that was POST-form syntax, not PUT — corrected from prior revision).
6. Client `PUT`s bytes directly to Spaces with the exact `required_headers`.
7. On success, client emits `message:send` with `media.url = public_url`.
8. Server-side validation on `message:send`: URL must match the bucket's CDN host pattern (`my-projects-media.sfo3.cdn.digitaloceanspaces.com`) and the object key must start with `flame_backend/{category}/{user_id}/...` matching the sender. Phase 1 does **not** do a HEAD existence check (Phase 2).

### Known security gaps accepted in Phase 1

- **No HEAD existence check.** A malicious client could send a `message:send` referencing a public_url whose object was never actually uploaded. Recipient sees a broken image. Mitigation: client always renders broken-image placeholder. Phase 2 closes this with HEAD check + Spaces event-driven verification.
- **CORS prerequisite.** DO Spaces bucket CORS must allow `PUT` from the app origin. Operator action: configure bucket CORS with `<AllowedMethod>PUT</AllowedMethod>`, `<AllowedHeader>*</AllowedHeader>`, `<AllowedOrigin>*</AllowedOrigin>` (or restrict to app domains). Spec call-out: implementation plan must include this as a manual step, verified before flag flip.

### Voice messages

m4a, 64kbps mono, max 60s. Recorded with `record` (already in pubspec). Client measures duration locally and computes waveform peaks during recording — no server-side analysis.

### Stickers and GIFs

- Stickers: existing endpoints stay. Flutter integrates `lib/realtime/sticker_picker.dart` into the chat input bar. On select, emit `message:send` with `type: "sticker", content: sticker_id`. Server resolves sticker URL on receive — broadcast carries the URL.
- GIFs: integrate Tenor API (free tier). New backend endpoint `GET /media/gif/search?q=...&limit=20` proxies Tenor (rate-limit per user; no API key on client). Selected GIF sends as `type: "gif"` (use `MessageType.GIF`) with `media.url = tenor_cdn_url` — no re-upload to Spaces.

### Old upload endpoints deprecation

`POST /chat/.../messages/image|video|audio|voice` are kept alive for one release as a fallback, removed in Phase 2.

## Flutter client architecture

### Riverpod refactor

`chat_screen.dart` becomes a `ConsumerStatefulWidget` (only for `TextEditingController` and `ScrollController`; never for app state). All `setState` calls in the chat screen are removed and replaced with provider reads/writes.

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

Persistent send queue backed by `SharedPreferences`. On every mutation, the entire queue is serialized to a single JSON key — fine at expected sizes (<100 pending entries).

Flow:
1. User taps send → message appended to outbox with `status: pending`, `client_message_id: uuid()`, `attempts: 0`.
2. UI immediately renders message in conversation with `pending` indicator.
3. If socket connected → call `socket.emitWithAck('message:send', payload).timeout(Duration(seconds: 8))`. Set `status: sending`.
4. On ack with `{ok: true, message: ...}` → update with canonical `message_id` + `server_timestamp`, set `status: sent`, remove from outbox.
5. On `TimeoutException` or socket disconnect → keep `status: pending`, `attempts++`. Max 5 attempts. After that mark `status: failed`, surface tap-to-retry affordance.
6. On ack with `{ok: false, error: {code: "TRANSIENT", retry_after_ms}}` → wait `retry_after_ms`, retry.
7. On ack with `{ok: false, error: {code: "BLOCKED" | "VALIDATION" | ...}}` (terminal) → mark `failed` with the error code surfaced in UI; no retry.

`outbox.flush()` runs on every `connection:ready`. Crash-safe: on cold start, anything `pending`/`sending` is reset to `pending` and re-flushed once the socket connects. Server-side idempotency makes replay safe.

**Dart API confirmation:** `socket_io_client: ^2.0.3+1` exposes `emitWithAck(event, data, ack: callback, ackTimeout: Duration)`. The implementation plan must verify the exact API at the pinned version; if the constructor differs, fall back to `emitWithAck(...)` returning `Future` wrapped with `.timeout()`.

### `SocketNotifier`

States: `disconnected | connecting | connected | reconnecting | failed`.

- Wraps the `socket_io_client` instance, exposes events as a stream other notifiers subscribe to via `ref.listen`.
- Auto-connects on app launch after auth restored.
- Auto-disconnects on logout, **never on lifecycle changes** — backgrounding does not disconnect; the OS suspends the socket and the library reconnects on foreground.
- On `auth:token_expiring` event → calls `authProvider.refresh()`, then emits `auth:token_refreshed`.
- On `auth:token_expired` or 401 from REST → triggers full re-auth flow.

### Auto-refresh on 401 (`package:http` interceptor strategy)

`package:http` does **not** have a native interceptor pattern. The current `ApiClient` is a singleton with explicit `_request()` private method that wraps all calls (`api_client.dart`).

Implementation:
- Wrap **all HTTP method calls** (`get`, `post`, `put`, `patch`, `delete`, `multipartRequest`) in `ApiClient` with a shared `_authenticatedRequest()` helper.
- `_authenticatedRequest` semantics:
  1. Issue request.
  2. If response is 401 and the path is not `/auth/refresh`:
     - Acquire mutex `_refreshMutex` (asyncio-style: a `Completer<void>` shared across concurrent callers; the first caller does the refresh, others `await` the same Completer).
     - First caller: call `/auth/refresh`. On success, store new tokens, complete the mutex with success. On failure, complete with error, fire `auth:logout`, redirect to login.
     - Retry the original request once with new token.
  3. Return the result.
- The mutex prevents N concurrent 401s from kicking off N concurrent refreshes.

(Switching to `dio` with native interceptors was considered and rejected for Phase 1 — would touch every service file. The wrapper approach is contained.)

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

**Tier 1 — Recoverable per-request** (validation, conversation not found, blocked user, payload too large): reply via ack with `{ok: false, error: {code, message}}`. Codes mirror `app/core/exceptions.py` enum.

**Tier 2 — Infrastructure transient** (Mongo timeout, Redis blip): one immediate retry inside the handler with 200ms timeout. If retry fails, ack `{ok: false, error: {code: "TRANSIENT", retry_after_ms: 2000}}`. Client outbox respects `retry_after_ms`. Log at WARN with `event_id`, `user_id`, `client_message_id`.

**Tier 3 — Programming errors** (unhandled exception): caught by global socketio error handler. Log at ERROR with full traceback; ack `{ok: false, error: {code: "SERVER_ERROR"}}`. Never let an exception kill the connection.

### Client-side error UX

- Per-message: `pending` → `sending` → `sent` → `read`. `failed` shows red exclamation + tap-to-retry.
- Connection banner: small non-blocking strip at top of chat. "Reconnecting…" (yellow), "Offline" (red, after 30s of failed reconnects), nothing when connected. Self-dismissing.
- No modal dialogs, no toasts for transient issues.

## Observability

Backend switches to structured JSON logs. New `app/core/logging.py` module wrapping `python-json-logger`. Every line includes `request_id`, `user_id`, `conversation_id`, `event`, `duration_ms`. The existing `print` statements in `app/core/redis.py` (lines 19, 24, 26 per audit) are removed as part of this work.

Log volume target per chat send: 1 INFO line on success, 1 WARN on transient retry, 1 ERROR on failure.

Lightweight metrics via `prometheus_client`:
- `chat_messages_sent_total{type}`, `chat_acks_latency_seconds` (histogram)
- `chat_idempotency_hits_total`
- `socket_connections_active` (gauge)
- `socket_disconnects_total{reason}`

Scrape endpoint at `/metrics`.

## Migration plan (expanded)

Schema-additive, dual-write transition window (one release).

### Schema changes on `Conversation`

Add `participants: List[Participant]` where `Participant` is:
```
{ user_id: str, last_read_message_id: str | null,
  last_read_at: datetime | null, unread_count: int,
  joined_at: datetime }
```

Existing fields **kept and dual-written** for the transition: `user1_id`, `user2_id`, `user1_unread_count`, `user2_unread_count`, `user1_muted_until`, `user2_muted_until`. Existing helper methods (`get_other_user_id`, `get_unread_count`, `increment_unread`, `reset_unread`) keep working, internally also updating the participant record.

After Phase 1 is fully rolled out (next release after the `CHAT_V2_ENABLED` flip), Phase 2 removes the legacy fields.

### One-shot migration script `scripts/migrate_chat_v2.py`

Inputs: read-write Mongo connection.

For each `Conversation`:

1. If `user1_id` is null or `user2_id` is null → skip and log WARN (orphaned conversation).
2. Confirm both user docs exist; if either was deleted, set the missing participant's `user_id` to a sentinel `"deleted_user"` placeholder with `unread_count=0`. Conversation is otherwise preserved.
3. Construct `participants[0]` for `user1_id`:
   - `unread_count = user1_unread_count`
   - `last_read_at` = most recent `Message.timestamp` in this conversation where `sender_id == user2_id AND status == READ`. If none, `null`.
   - `last_read_message_id` = `_id` of that message (or `null`).
   - `joined_at` = `Conversation.created_at`.
4. Construct `participants[1]` for `user2_id` analogously.
5. `Conversation.participants = [p0, p1]`. Save.

Edge cases:
- Conversation with zero messages: both participants get `last_read_message_id=null`, `last_read_at=null`, `unread_count=0` (matches existing zero values).
- Conversation where one user is "deleted_user": the live user's participant is computed normally; the deleted participant has `unread_count=0`, all read fields `null`.
- Idempotency: script checks `if conversation.participants` is non-empty, skips. Safe to re-run.

Run order: dev → staging → prod (with maintenance flag) → flip `CHAT_V2_ENABLED` → soak → Phase 2 cleans up.

### Forward compatibility

`client_message_id` is forward-going only — no backfill. Legacy messages have no `client_message_id` and don't need one (they're already canonical).

`MessageType.GIF` is added to the enum if not present; no migration needed (new field used only for new messages).

## Rollout & feature flags (clarified)

Two coordinated flags:

1. **Backend env var `CHAT_V2_ENABLED`** — controls which code path serves `/ws/socket.io/` vs the legacy `/ws`. When `false`, the new realtime app is not mounted. When `true`, the legacy `/ws` path returns 410 Gone (during the kill-switch window) and `/ws/socket.io/` is live.

2. **Client runtime config** — `GET /v1/config` (new endpoint) returns `{chat_v2_enabled: bool}`. Flutter checks this on app start and routes to either `socket_io_client` (new) or `web_socket_channel` (old) accordingly. **Both code paths ship in the Phase 1 release** — the old `websocket_service.dart` is **kept but not deleted in Phase 1's first release**, deletion is in the *following* release once the flag has been on for at least 7 days. (Correction from prior revision, which had the file deleted while still claiming a runtime fallback — internally inconsistent.)

The compile-time `--dart-define=APP_ENV=local|prod` is unrelated; it controls API base URL only, not chat version selection.

## Testing strategy

This is the first real test foundation in either repo, scoped to chat.

### Backend (`tests/realtime/`)

`pytest-asyncio` + `socketio.AsyncSimpleClient` for in-process integration tests against a real Mongo (testcontainers) and real Redis (testcontainers).

Test cases:
- Happy path: send → ack → recipient gets `message:new` → recipient marks read → sender gets `read:update`.
- Idempotency: same `client_message_id` twice (same socket, then across sockets) → same canonical id, one DB row, one broadcast (asserted by recipient client receiving exactly one event during a 2s window).
- Mirror echo skip: sender's other connected sid gets `message:sent`; the originating sid does not.
- Offline delivery: recipient connects after sender → queue replays exactly once even if recipient connects from two devices simultaneously (drain locked via `SET NX` on `queue:lock:{user_id}` 5s TTL).
- Multi-device cap: 4th connection evicts oldest; the evicted sid receives `force_disconnect`.
- Typing TTL: `typing:start` then no events → recipient receives `typing:update {is_typing: false}` within 5s.
- Typing on disconnect: user emits `typing:start`, then disconnects → peer receives stop within 1s.
- Token refresh: `auth:token_expiring` arrives at `exp - 120s` from connect time; client refreshes; old timer cancelled; new timer scheduled.
- Banned user enforcement: ban a connected user → all sids disconnect within 2s without requiring an outbound event.
- Read monotonicity: device A writes `last_read_message_id=X`, device B writes `Y < X` after → final state is X.
- Blocked user: send to peer who blocked sender → ack `ok: false, code: BLOCKED`; no broadcast.
- Reactions/pins migration: emit reaction REST call → peer receives `reaction:update` over Socket.IO (verifies the notify_* migration).

Target: ~25 tests. Suite runs in <15s on CI.

### Flutter

- `outbox_test.dart`: enqueue, ack success/failure (terminal vs transient), retry exponential, max-attempts, persistence round-trip across simulated app kill.
- `socket_client_test.dart`: state machine transitions with mocked socket; verifies reconnect events do not duplicate outbox flushes.
- `messages_provider_test.dart`: pagination, optimistic insert, dedup on echo, monotonic last_read application.
- `auth_refresh_test.dart`: mutex correctness — N concurrent 401s trigger 1 refresh.

Target: ~18 tests.

## Done criteria (testable)

Phase 1 is shippable when **all** of the following are true and the verification commands return success:

1. **All implementation merged behind `CHAT_V2_ENABLED`.** Verify: `grep -r CHAT_V2_ENABLED app/` finds the gate; flipping it to false restores legacy `/ws` behavior in a smoke test.
2. **Backend test suite passes.** Verify: `pytest tests/realtime/ -v` exits 0; coverage on `app/realtime/` ≥80%.
3. **Flutter unit tests pass.** Verify: `flutter test` exits 0.
4. **Manual QA matrix passed.** Each row has a reproducible recipe and a verifiable post-condition:
   - **Airplane mode flush:** enable airplane mode, type+send 3 messages (each gets `pending` indicator), disable airplane mode, observe socket reconnect within 5s, all 3 messages transition `pending → sending → sent` within another 3s. Verify in Mongo: exactly 3 new `messages` docs with the 3 `client_message_id`s.
   - **Force-quit replay:** start a send, force-quit during the 8s ack window, reopen app. Outcome must be one of: (a) message has `status: sent` (server received and acked, replay was a no-op via idempotency), or (b) message has `status: pending` and re-sends successfully. Verify in Mongo: exactly 1 `messages` doc with that `client_message_id`.
   - **Two-device sync:** log in same user on phone + simulator. Send from phone. Within 1s, simulator's chat list updates `last_message_at` and chat screen shows the message. Both devices' `messages` arrays for the conversation are identical.
   - **Long-lock send:** type a long message, lock device for 90s, unlock, send. Message acks within 3s of unlock; no disconnect-reconnect storm in logs.
5. **Idempotency load test:** `tests/realtime/test_idempotency_load.py` replays the same `message:send` event 100 times concurrently → asserts `Message.count_documents({client_message_id: ...}) == 1` and recipient client received exactly 1 `message:new` event during the test window.
6. **CORS configured on Spaces bucket** for `PUT` from app domains. Verify: `curl -X OPTIONS ...` returns the expected `Access-Control-Allow-*` headers.
7. **No `print` statements remain in `app/core/`.** Verify: `grep -rn 'print(' app/core/` returns nothing.

## Open questions

- **Background sync of `User.is_online`:** the spec says a 60s task derives this from Redis presence for legacy reports. Confirm whether any consumer actually reads `User.is_online` (audit suggests no — it's written but not read on critical paths). If no consumer, the sync task can be skipped and the field allowed to drift (Phase 2 will drop the field).
- **Redis keyspace notifications:** does the operator's Redis allow `notify-keyspace-events Ex`? If managed Redis (e.g. DigitalOcean managed) doesn't support it, fall back to in-process `asyncio.sleep(10)` for the offline grace timer (already specified as fallback).
- **Tenor API key:** free tier requires no key but throttles aggressively. Confirm whether traffic warrants the keyed tier; if so, add `TENOR_API_KEY` to backend env. Phase 1 ships keyless and revisits in Phase 2 if rate-limited.

## References

- Reference WebSocket implementation: `/Users/davis/Desktop/Personal/language_exchange_backend_application/socket/socketHandler.js`
- Backend audit findings: `app/auth/`, `app/chat/`, `app/community/service.py:208-335`, `app/core/redis.py`
- Client audit findings: `lib/services/websocket_service.dart`, `lib/screens/chat/chat_screen.dart`, `lib/services/api_client.dart:273-296`
- Spec review iteration 1: see review report (7 critical issues, 11 material gaps, 8 nits) — all addressed in this revision.
