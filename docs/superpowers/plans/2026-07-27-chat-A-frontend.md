# Chat-A Frontend — Edit/Delete UI · Typing · Presence · Unread Badges

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Checkbox steps.

**Goal:** Wire the frontend to the finished Chat-A backend: edit/delete message UI, typing indicators, online-presence display, and unread badges — over the existing `/flame` socket + REST.

## Global Constraints
- Frontend repo `~/Desktop/Flame/flame_front_app`. Backend endpoints/events are live on `feat/flame-chat` (run locally to test; unit-test with mocks).
- Gate socket-driven UI on `EnvConfig.current.chatEnabled` (local on, prod off) where a connection is involved; presence/typing must degrade gracefully when the socket is disconnected (polling remains).
- Commands: `flutter test`, `flutter analyze <paths>`. Guard every socket/async callback with `if (!mounted) return;`.
- Reference (read): `lib/services/flame_socket_service.dart`, `lib/screens/chat/chat_screen.dart`, `lib/screens/chat/widgets/{message_bubble,typing_indicator,chat_input}.dart`, `lib/services/chat_service.dart`, `lib/models/message.dart`, `lib/screens/chat/matches_screen.dart`, `lib/screens/main_shell.dart`, `lib/providers/chat_provider.dart`.

**Backend contract recap:** socket server→client events on `/flame`: `message:new`, `message:edited`, `message:deleted`, `typing`/`stopTyping` ({from, conversation_id}), `presence` ({user_id, online}), `presence:bulk` ({online:[ids]}), `read`. Client→server: `typing`/`stopTyping`/`markRead` ({to, conversation_id}). REST: `PATCH /messages/:id {text}`, `DELETE /messages/:id?scope=me|everyone`. Message JSON now has `is_edited`, `edited_at`, `is_deleted`.

---

### Task 1: Edit & delete (service + parsing + UI + socket)
**Files:** `lib/services/chat_service.dart`, `lib/models/message.dart`, `lib/services/flame_socket_service.dart`, `lib/screens/chat/chat_screen.dart`, `lib/screens/chat/widgets/message_bubble.dart`; tests for the service shapes + Message parsing.
- `chat_service`: `editMessage(messageId, text)` → `PATCH /messages/:id {text}` → `Message`; `deleteMessage(messageId, {scope='me'})` → `DELETE /messages/:id?scope=` → `Message`. (Adjust any pre-existing edit/delete methods to this real contract.)
- `Message.fromJson`: ensure `isEdited` (json['is_edited']), `editedAt` (json['edited_at']), `isDeleted` (json['is_deleted']) parse. Add fields if missing (backward compatible).
- `flame_socket_service`: expose `message:edited` and `message:deleted` callbacks/streams (parse via Message.fromJson).
- `chat_screen`: un-hide the Edit + Delete actions in the message long-press sheet (removed for text-only MVP); wire Edit → a text edit dialog → `editMessage`, then replace the message in `_messages`; Delete → a "Delete for me / Delete for everyone" sheet → `deleteMessage(scope)`, then update `_messages`. Handle incoming `message:edited` (replace by id) and `message:deleted` (mark deleted) for the open conversation. Only show Edit/Delete on the current user's own messages, and (optionally) only within the time windows.
- `message_bubble`: render an "edited" label when `isEdited`, and a "message deleted" tombstone when `isDeleted` (instead of the text).
- TDD the pure bits (service request shapes via MockClient; Message.fromJson edited/deleted). Screen/socket wiring: analyze + suite + review.
- Commit `feat(chat): edit + delete message UI + edited/deleted socket handling`.

### Task 2: Typing indicators
**Files:** `lib/services/flame_socket_service.dart` (expose typing in/out — likely already present), `lib/screens/chat/chat_screen.dart`, `lib/screens/chat/widgets/chat_input.dart`, `typing_indicator.dart`.
- Emit `typing {to: otherUserId, conversation_id}` on chat-input text change, throttled: emit once on first change, reset a 3s idle timer that emits `stopTyping`; emit `stopTyping` on send + dispose.
- On incoming `typing` for the open conversation, show the `TypingIndicator` widget; clear on `stopTyping` or a 5s safety timer. Guard with mounted.
- analyze + suite + review. Commit `feat(chat): typing indicators over the socket`.

### Task 3: Online presence display
**Files:** `lib/services/flame_socket_service.dart` (expose `presence` + `presence:bulk`), `lib/screens/chat/chat_screen.dart` (header dot), `lib/screens/chat/matches_screen.dart` (conversation-row dot), a small presence state holder if needed.
- Seed online state from `other_user.is_online` / conversation data, then update live from `presence` events (a `Map<userId,bool>` in a provider or the screen). `presence:bulk` sets the initial set on connect.
- Show a small green dot on the chat header avatar + conversation-list rows when the partner is online. Respect that the backend already gates on the sender's setting (so "offline" simply means no online event).
- analyze + suite + review. Commit `feat(chat): online presence dot in header + conversation list`.

### Task 4: Unread badges
**Files:** `lib/providers/chat_provider.dart` (or a new `chat_unread_provider.dart`), `lib/screens/chat/matches_screen.dart`, `lib/screens/main_shell.dart`.
- `chatUnreadCountProvider` = sum of `unreadCount` across conversations (watch conversationsProvider). Conversation-list rows already have `unreadCount` — show a per-row badge.
- Re-introduce the Chat nav-item dot badge in `main_shell` (it existed pre-Phase-5), driven by `chatUnreadCountProvider`, only when `chatEnabled`. Live-update: increment on socket `message:new` for a non-open conversation; clear when the thread opens / `markRead`.
- Unit-test the sum provider; analyze + suite + review. Commit `feat(chat): unread badges (conversation rows + Chat tab)`.

### Task 5: Verification
- `flutter test` full suite green; `flutter analyze` no new issues in touched files; manual local run against the backend (send/edit/delete/typing/presence/unread). Commit any fixups.

## Self-Review
Covers all four A frontend features on the finished backend + socket. Pure bits TDD'd; screen/socket wiring analyze+review-gated (widget socket behavior isn't cleanly unit-testable). Gated on chatEnabled; graceful when socket down. ✅
