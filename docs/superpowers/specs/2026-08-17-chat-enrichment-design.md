# Chat Enrichment — Design (Phase B)

**Date:** 2026-08-17
**Phase:** B, following A (matching & safety, shipped)
**Repos:** `~/Projects/BananaTalk/backend` (the `flame/` sub-app) and `~/Desktop/Flame/flame_front_app`
**Predecessor spec:** `docs/superpowers/specs/2026-08-16-matching-and-safety-design.md`

## Problem

Phase A gave chat a front door. It works — send, receive, edit, delete, reactions,
read receipts, typing, and a live socket inside an open conversation. What remains
is the gap between that and a chat people expect.

The gap has two different shapes, and they should not be confused:

1. **Something is broken in front of users.** Realtime exists only while a
   conversation is open, so the Messages list and the unread badge never update
   live. This is a defect, not a missing feature.
2. **Endpoints the shipped app already calls have no backend.** Media messages,
   pin and mute are wired in `chat_service.dart` and reachable from the app's
   code today. They are latent 404s.

Everything else is new product surface.

## What already works — do not rebuild

Verified in the codebase, not assumed:

| Capability | Where |
|---|---|
| Send / receive text | `chatService.sendMessage`, `getMessages` |
| **Reply** | `Message.replyTo`, `sendMessage({replyTo})`, serialised as `reply_to` |
| Edit / delete | `chatService.editMessage`, `deleteMessage` |
| Reactions | `addReaction`, `removeReaction` |
| Read receipts | `markRead`, `unreadCount[]` per participant |
| Typing indicators | `flameSocket` `typing` / `stopTyping` relays |
| Socket transport | `/flame` namespace, verified reachable; client connects and logs `[FlameSocketService] connected` |
| Block enforcement | `visibilityService` across all surfaces (Phase A) |

An earlier draft of this spec listed **reply** as missing. That was wrong — it is
fully implemented end to end.

## Scope and order

**B1 → B2 → B3 → B5.** B4 (stickers) is cut — see below.

B1 first because it fixes a live defect. B2 and B3 close endpoints the app already
calls. B5 is new product surface.

---

## B1 — Realtime completeness

### Problem

`FlameSocketService.connect()` is called only from `ChatScreen`
(`chat_screen.dart:236`). Outside an open conversation nothing is listening, so:

- the Messages list does not update when a message arrives
- `chatUnreadCountProvider` sums `unreadCount` from a cached conversations list
  that only refreshes on app start or pull-to-refresh, so the badge is stale

The backend is not at fault: it returns `unread_count` per conversation and
increments it on send, and the `/flame` namespace accepts connections. Nothing is
listening.

### Design

**One socket for the app, owned by a Riverpod provider.** Connected when auth
succeeds, disposed on logout.

`ChatScreen` **stops opening its own socket** and subscribes to the shared one.
Two sockets per user would double every `areBlocked` lookup in
`flameSocket.emitToReceiver` and double the presence fan-out for no benefit.

Responsibilities of the app-level listener:

- `message:new` → update `conversationsProvider` (last message, timestamp,
  unread count) so the list and badge move without a refetch
- `message:edited` / `message:deleted` → update the cached conversation preview
- `read` → clear the unread count for that conversation
- `presence` / `presence:bulk` → online indicators in the list

### Lifecycle — the part that will bite

- **Backgrounding.** Socket.IO reconnects on resume, but the access token may
  have expired while backgrounded. The listener must re-authenticate with a fresh
  token rather than retrying a dead one.
- **Token refresh mid-session.** `ApiClient` already refreshes proactively; the
  socket must pick up the new token, which means reconnecting with new auth.
- **Logout.** The socket must be torn down, or the next user inherits it.
- **No socket ≠ no chat.** Every realtime path is an enhancement over the REST
  state. If the socket is down, the app must still work through refetching.

### Out of scope

Offline queueing and optimistic send. The app already shows a `sending` status;
making it durable across a restart is a separate problem.

---

## B2 — Media messages

### Contract (already fixed by the shipped app)

`chat_service.dart` calls these through `ApiClient.uploadFile` (multipart). The
backend must match them exactly:

```
POST /conversations/:id/messages/image   field: image   + optional reply_to_id
POST /conversations/:id/messages/video   field: video   + optional thumbnail
POST /conversations/:id/messages/audio   field: audio
POST /conversations/:id/messages/voice   field: voice
```

Each returns a `Message` the app parses with `Message.fromJson`.

### Design

- **`Message.messageType`** widens from `enum: ['text']` to
  `['text', 'image', 'video', 'audio', 'voice']`.
- New fields for the media URL, and for video a thumbnail URL and duration; voice
  carries a duration. The app's `Message` model already reads `image_url`,
  `video_url`, `audio_url` and `media_info` — match those keys rather than
  inventing new ones.
- **Storage reuses the proven path.** `userService.uploadPhoto` already does
  multer → MIME allowlist → size cap → S3 (DigitalOcean Spaces) → public URL.
  Media messages follow the same shape, with per-kind limits rather than one
  global limit: images are not videos.
- **Routes reuse `upload.single(field)`**, exactly as `users.js` does for photos.

### Enforcement carries over

Every media send goes through the same guards as a text send:
`assertCanInteract` for blocks, and the ended-match check added in Phase A. A
media route that skips them reopens a hole Phase A closed.

### Decisions to make in the plan

- Size caps per kind, and what happens on exceed (413 vs 422 — follow the
  existing `ValidationError` → 422 convention).
- Whether the server generates a video thumbnail when the client omits one, or
  rejects. Recommendation: accept the client's, do not transcode — transcoding is
  a service, not a feature.

---

## B3 — Conversation controls

### Contract (already fixed by the shipped app)

```
POST   /conversations/:id/pin        { message_id }      pin a message
DELETE /conversations/:id/pin/:msgId                     unpin
POST   /conversations/:id/mute       { duration? }       mute
DELETE /conversations/:id/mute                           unmute
```

### Design

Copy BananaTalk's per-user array pattern, which is proven in production there:

```
mutedBy:    [{ user, mutedUntil, mutedAt }]
pinnedBy:   [{ user, messageId, pinnedAt }]
archivedBy: [{ user, archivedAt }]
```

Per-user rather than per-conversation: muting is one participant's choice and must
not affect the other.

- **Mute** suppresses push notifications for that user only; the conversation
  still appears and still accrues unread count.
- **Pin** sorts the conversation, or the message within it, first for that user.
- **Archive** filters out of the default list — additive to the existing
  block/ended-match `$nin` in `listConversations`, not a replacement.

Archive has no app caller yet; it is included because the model change is the same
edit and splitting it would mean touching `Conversation` twice.

---

## B5 — Search, forward, disappearing

New product surface. Each is independent; any can be cut.

**Search.** A Mongo text index on `Message.text`, scoped to the caller's own
conversations. Must respect blocks and ended matches — a search that returns
messages from a blocked pair reopens Phase A's hole through a side door.

**Forward.** Copy a message into another conversation with attribution. Cheap.
The interesting question is whether forwarding out of a since-blocked conversation
is allowed; recommendation: no.

**Disappearing messages.** A TTL index on an `expiresAt` field, plus a client that
hides expired messages before the sweep runs — TTL deletion is not immediate and
can lag by a minute. The one feature here that genuinely fits dating.

---

## B4 — Stickers: CUT

Not in scope. Recorded here so the decision is not re-litigated.

The app calls five sticker endpoints (`/stickers/packs`, `/stickers/packs/:id`,
`/stickers/my-packs`, and POST/DELETE on `/stickers/my-packs/:id`). They will
continue to 404, which is harmless: nothing in the reachable UI surfaces a
sticker picker. `ChatInput` is deliberately text-only and the picker lives in
`ChatV2Screen`, which nothing navigates to.

Delivering them would mean a content subsystem — pack catalog, per-user
ownership, asset hosting, artwork licensing — for roughly half of this phase's
total cost. BananaTalk has stickers because it is a language-learning product
where they serve a pedagogical purpose; Flame inherited the client code, not the
rationale.

If this is ever revisited, the minimum viable version is a seeded read-only
catalog with per-user ownership and no user-generated packs.

## Testing

Following `flame/__tests__` conventions (`node:test` + `mongodb-memory-server`),
plus the standing corrections learned in Phase A:

- fixture user names must be ≥2 characters (`User.name` has `minlength: 2`)
- integration tests must set the S3 env vars before requires
- every required service must be cleared from the require-cache array

Per phase:

- **B1** — the app-level listener updates the conversation list and unread count
  on a simulated `message:new`; teardown on logout; reconnect with a refreshed
  token. App-side, with a fake socket rather than a live one.
- **B2** — each media kind stores and returns its URL; oversize and wrong-MIME are
  rejected; **a blocked pair and an ended match are rejected on every media route**,
  not only on text.
- **B3** — mute affects only the muting user; pin sorts for that user only;
  archive filters without disturbing the block/ended-match exclusions.
- **B5** — search returns only the caller's conversations and excludes blocked and
  ended pairs; disappearing messages are hidden client-side before TTL sweeps.

## Deployment note learned the hard way

Phase A shipped broken because `flame_db` already contained collections from an
earlier Flame schema, carrying unique indexes on differently-named fields. Every
test passed — `mongodb-memory-server` starts empty, so no test could see them.

**Before deploying any new collection or index in this phase, run
`flame/scripts/drop-legacy-indexes.js` against the target database and read the
report.** Model definitions are not evidence about production data.
