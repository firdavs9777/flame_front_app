# Chat Realtime UX (Sub-project A) — Design Spec

> Date: 2026-07-27 · Spans the flame frontend (`~/Desktop/Flame/flame_front_app`) and the flame
> backend sub-app (`~/Projects/BananaTalk/backend/flame`, branch `feat/flame-chat`).
> Builds on the shipped chat (REST + reactions + reply) and the isolated `/flame` Socket.IO namespace.

## 1. Goal

Add four realtime UX features to chat, on top of the existing `/flame` socket: **typing indicators**,
**online presence**, **edit & delete messages**, and **unread badges**. No new infrastructure — all
build on the realtime channel already in place. (Media messages remain deferred on the Spaces fix.)

## 2. Approved decisions

- **Presence:** visible only to a user's **conversation partners**, and only when the user's **Show
  Online Status** setting is on. Users with it off appear offline to everyone.
- **Edit/delete:** edit own text ≤ 15 min after send; delete-for-everyone ≤ 1 hr; delete-for-me
  anytime. Edited state shows an "edited" label; a for-everyone delete leaves a "message deleted"
  tombstone. All synced live over the socket.

## 3. Features

### A.1 Typing indicators (frontend-only)
The `/flame` socket already relays `typing`/`stopTyping` (client→server→the other participant's room),
and `FlameSocketService` already exposes `emitTyping`/`emitStopTyping` + incoming typing callbacks —
they were built but not wired to the UI. Wire them:
- Emit `typing {to: otherUserId, conversation_id}` on text-field change (throttled: emit once, then a
  3s idle timer emits `stopTyping`); emit `stopTyping` on send and on dispose.
- On incoming `typing` for the open conversation, show the existing `TypingIndicator` widget; clear it
  on `stopTyping` or after a 5s safety timeout.
No backend change.

### A.2 Online presence (backend socket + frontend display)
- **Backend (`flame/socket/flameSocket.js`):** maintain an in-memory map `userId → connection count`.
  On connect: increment; if the user's `showOnlineStatus` pref is true, emit `presence {user_id,
  online:true}` to each of the user's conversation-partner rooms, and send the connecting user a
  `presence:bulk` of which of their partners are currently online (respecting each partner's setting).
  On disconnect: decrement; when it hits 0, emit `presence {user_id, online:false}` to partners.
  "Partners" = the other participant of each of the user's `Conversation`s (looked up once on connect).
  A small `flame/services/presenceService.js` (or a helper in the socket file) holds the online map +
  the partner lookup. Gate every outward presence on the sender's `showOnlineStatus`.
- **Frontend:** show an online dot in the chat header and conversation-list rows. Seed from the
  `is_online` field already on the user/other_user, then update live from `presence` events. Respect
  the local Show-Online setting for the current user's own broadcast (already emitted server-side).

### A.3 Edit & delete messages (backend endpoints + frontend UI)
- **Backend (`flame/` chat):**
  - `PATCH /messages/:id` body `{text}` — sender only, message not deleted, `created_at` within 15 min;
    else `FlameError('FORBIDDEN'|'EXPIRED', …)`. Sets `isEdited=true`, `editedAt`. Returns the updated
    message; emits `message:edited` to the other participant's room.
  - `DELETE /messages/:id?scope=everyone|me` — `me` (default): add caller to `deletedFor[]` (hidden for
    them only), anytime. `everyone`: sender only, within 1 hr → `isDeleted=true` (tombstone). Returns
    the updated message; `everyone` emits `message:deleted`.
  - New `emitMessageEdited`/`emitMessageDeleted` in `flameSocket.js`; controller emit hooks (guarded).
  - `toMessage` already carries `is_edited`?/`is_deleted` — add `is_edited`, `edited_at`, `is_deleted`
    to the shape if missing so the frontend can render state.
- **Frontend:** un-hide the edit + delete actions in the message long-press sheet (removed for the
  text-only MVP); wire edit → `PATCH`, delete → a small "delete for me / for everyone" chooser →
  `DELETE`. Handle `message:edited`/`message:deleted` socket events (update `_messages`). Render an
  "edited" label and a "message deleted" tombstone. `Message` already has `isEdited`/`isDeleted`.

### A.4 Unread badges + conversation list (mostly frontend)
- The backend already tracks per-conversation `unread_count` (incremented on send, zeroed on
  `PUT /read`). No backend change beyond what exists.
- **Frontend:** conversation-list rows show their `unread_count` as a badge; a `chatUnreadCountProvider`
  sums unread across conversations; the Chat nav tab shows that total as a dot badge (re-introduce the
  badge on the `main_shell` Chat item, gated on `chatEnabled`). Live-update: increment on socket
  `message:new` for a non-open conversation; clear when a thread is opened / `markRead` runs.

## 4. Architecture / units

- Backend: `flame/socket/flameSocket.js` gains presence tracking + edit/delete emit helpers; a small
  `presenceService` unit holds the online map + partner lookup (testable in isolation); `chatService`
  gains `editMessage`/`deleteMessage` (with the time-limit + authorization rules, unit-tested like the
  existing service methods); `chatController` + `routes/messages.js` gain the PATCH/DELETE routes.
- Frontend: `FlameSocketService` (extend: expose edited/deleted + presence streams); chat_screen wiring
  (typing, presence, edit/delete UI, socket event handling); a `chatUnreadCountProvider`; conversation
  list + nav badge display.

## 5. Testing

- Backend: `editMessage`/`deleteMessage` service tests (sender-only, time-limit expiry, for-me vs
  for-everyone) + endpoint tests (`node --test`, mirroring conversations.test.js) — auth 401, forbidden
  403, expired 4xx, validation 422. `presenceService` unit test (online map increment/decrement,
  partner filtering, setting gate). Socket relay code is structurally reviewed (no socket client in the
  test harness).
- Frontend: `Message.fromJson` edited/deleted parsing; `chatUnreadCountProvider` sum logic;
  service-shape tests for edit/delete via MockClient. Screen/socket wiring verified by analyze + full
  suite + review (widget socket behavior isn't cleanly unit-testable), plus manual local run.

## 6. Sequencing (implementation plan will follow)

1. Backend: edit/delete endpoints + emits + tests.
2. Backend: presence (presenceService + socket wiring) + tests.
3. Frontend: edit/delete UI + Message edited/deleted parsing + socket handling.
4. Frontend: typing indicators wiring.
5. Frontend: presence display.
6. Frontend: unread badges (provider + list + nav badge).

Backend rounds land on `feat/flame-chat`; frontend on the app branch. Each round independently tested.

## 7. Out of scope (deferred)

- Media/voice messages (Spaces fix), forward, pin, message search, polls, corrections/vocab — the
  BananaTalk long tail. Push notifications (sub-project B) and email (C) are separate.
- Isolation constraint from the realtime work still holds: all socket code stays on the `/flame`
  namespace; zero effect on the BananaTalk / Fitbowl sockets.
