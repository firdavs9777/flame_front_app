# Chat-FE-1 — Wire Frontend to the Flame Chat Backend

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Reconcile the Flame chat frontend (built for a different contract) with the real flame chat backend (on `feat/flame-chat`): fix the data-layer (`Message.fromJson`, `ChatService`), the send data-loss + ordering bugs in the chat screen, hide the features the backend doesn't have, and add message polling. The Chat tab stays hidden until backend go-live.

**Backend contract (live on `feat/flame-chat`, snake_case, envelope `{success,data}` already unwrapped by ApiClient → service reads `response.data`):**
- `GET /conversations?limit&offset` → `{conversations:[{id, other_user_id, other_user:{id,name,photos:[url],is_online,...}, last_message:(msg|null), last_message_at, unread_count, created_at}], pagination:{total,limit,offset,has_more}}`
- `POST /conversations {user_id}` → 201 `{conversation}`
- `GET /conversations/:id/messages?limit&offset` → `{messages:[msg], pagination:{...}}` (NEWEST first)
- `POST /conversations/:id/messages {text, reply_to?}` → 201 `{msg}`
- `PUT /conversations/:id/read` → `{marked}`
- `POST /messages/:id/reactions {emoji}` / `DELETE /messages/:id/reactions` → `{msg}`
- MSG: `{id, conversation_id, sender_id, receiver_id, text, message_type, reactions:[{user_id,emoji}], reply_to:(id|null), read, read_at, created_at}`

## Global Constraints

- Frontend repo `~/Desktop/Flame/flame_front_app`. Backend is NOT deployed — verify via unit tests (mock HTTP), not live prod.
- Preserve the committed realtime guard (`EnvConfig.realtimeEnabled`) and the StoryTray in matches_screen (both just committed).
- Commands: `flutter test <path>`, `flutter analyze <paths>`.

---

### Task 1: Reconcile `Message.fromJson` to the backend contract

**Files:** Modify `lib/models/message.dart`; Test `test/models/message_parsing_test.dart` (create).

**Deltas to fix in `Message.fromJson` (lib/models/message.dart:36-63):**
- `content` → read `json['text'] ?? json['content'] ?? ''`.
- `timestamp` → read `json['created_at'] ?? json['timestamp']` (keep the DateTime.parse + now() fallback).
- `type` → read `json['message_type'] ?? json['type']`.
- `status` → backend has no `status`; derive from `read`: if `json['read'] == true` → `MessageStatus.read`, else fall back to `MessageStatus.fromString(json['status'])`.
- `reply_to` → **backend sends a scalar id string or null, NOT an object**. The current `ReplyTo.fromJson(json['reply_to'])` casts to Map and will THROW on a string. READ the real `ReplyTo` class first, then guard: only call `ReplyTo.fromJson` when `json['reply_to'] is Map`; when it's a `String`, construct a minimal `ReplyTo` carrying just that id (add a lightweight constructor/factory if needed, e.g. `ReplyTo.fromId(String)`), else null. The message must parse without throwing whether `reply_to` is null, a string id, or (future) an object.

- [ ] **Step 1: Write failing test** — `test/models/message_parsing_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/message.dart';

Map<String, dynamic> _backendMsg({dynamic replyTo}) => {
      'id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 'u1',
      'receiver_id': 'u2',
      'text': 'hello there',
      'message_type': 'text',
      'reactions': [{'user_id': 'u2', 'emoji': '❤️'}],
      'reply_to': replyTo,
      'read': true,
      'read_at': '2026-07-20T10:00:00.000Z',
      'created_at': '2026-07-20T09:59:00.000Z',
    };

void main() {
  test('parses backend snake_case message fields', () {
    final m = Message.fromJson(_backendMsg());
    expect(m.id, 'm1');
    expect(m.senderId, 'u1');
    expect(m.content, 'hello there');          // from `text`
    expect(m.type, MessageType.text);          // from `message_type`
    expect(m.status, MessageStatus.read);      // derived from `read: true`
    expect(m.timestamp.year, 2026);            // from `created_at`
    expect(m.reactions.length, 1);
    expect(m.reactions.first.emoji, '❤️');
  });

  test('reply_to as a scalar id does not throw and is captured', () {
    final m = Message.fromJson(_backendMsg(replyTo: 'm0'));
    expect(m.replyTo, isNotNull);
    // The referenced id is retained (via whichever field the ReplyTo class exposes).
    expect(m.replyTo.toString().contains('m0') || (m.replyTo as dynamic).messageId == 'm0', isTrue);
  });

  test('null reply_to is fine', () {
    final m = Message.fromJson(_backendMsg(replyTo: null));
    expect(m.replyTo, isNull);
  });

  test('unread message derives a non-read status', () {
    final j = _backendMsg()..['read'] = false;
    final m = Message.fromJson(j);
    expect(m.status == MessageStatus.read, isFalse);
  });
}
```

(The implementer may adjust the reply-id assertion to match the actual `ReplyTo` API discovered when reading the model — the intent is fixed: scalar id parses without throwing and the id is retained.)

- [ ] **Step 2: Run → fails.** `flutter test test/models/message_parsing_test.dart` (content/type/status/created_at wrong; scalar reply_to throws).
- [ ] **Step 3: Implement** the deltas above in `Message.fromJson` (and mirror the reply-to guard so `toJson` stays consistent if it serializes reply_to).
- [ ] **Step 4: Run → passes.**
- [ ] **Step 5: Guard the model suite.** `flutter test test/models/` (existing model tests still green).
- [ ] **Step 6: Analyze + commit.**

```bash
git add lib/models/message.dart test/models/message_parsing_test.dart
git commit -m "fix(chat): parse Message from backend contract (text/created_at/message_type/read, scalar reply_to)"
```

---

### Task 2: Reconcile `ChatService` to the backend endpoints

**Files:** Modify `lib/services/chat_service.dart`; Test `test/services/chat_service_test.dart` (create).

**Make `ChatService` injectable** so it's testable: add a constructor `ChatService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();` (mirror how other code uses `ApiClient.testInstance(httpClient: MockClient(...))`, see `test/services/api_client_refresh_test.dart`).

**Endpoint fixes:**
- `getMessages`: query `offset` (int, not `before`); read `data['pagination']['has_more']`. Add an `offset` param.
- `sendMessage`: body `{ 'text': content }` + `reply_to` (not `content`/`type`/`reply_to_id`).
- `markMessagesAsRead`: `PUT /conversations/:id/read`, no body (drop `message_ids`).
- `addReaction`/`removeReaction`: path `/messages/:messageId/reactions` (no conversation segment); return `Message.fromJson(response.data)` (the updated message).
- Add `createConversation(String userId)`: `POST /conversations` body `{ 'user_id': userId }` → `Conversation.fromJson(response.data)`.
- `getConversations` is already correct — leave it.

- [ ] **Step 1: Write failing test** — `test/services/chat_service_test.dart` using `MockClient` to assert the request shape and parse a canned response for: sendMessage (posts `text`+`reply_to`, parses returned msg), getMessages (uses `offset`, reads `pagination.has_more`), markMessagesAsRead (PUT, no body), addReaction (path `/messages/:id/reactions`, returns Message), createConversation (posts `user_id`, returns Conversation). Assert against `MockClient` captured `request.url`/`request.body`. Model the harness on `test/services/api_client_refresh_test.dart` (ApiClient.testInstance + MockClient), constructing `ChatService(apiClient: testApiClient)`.
- [ ] **Step 2: Run → fails.**
- [ ] **Step 3: Implement** the constructor + endpoint fixes.
- [ ] **Step 4: Run → passes.**
- [ ] **Step 5: Analyze + full suite + commit.**

```bash
git add lib/services/chat_service.dart test/services/chat_service_test.dart
git commit -m "fix(chat): wire ChatService to real flame endpoints (offset paging, text body, PUT read, reaction paths, createConversation)"
```

---

### Task 3: Data-layer verification

- [ ] `flutter test` (whole suite) green; `flutter analyze` no new issues in the touched files. Commit any fixups (stage only touched files).

---

## Deferred to FE-1b / go-live (NOT in this plan — tracked)

These are the screen-level + rollout pieces, to do after the data layer is correct and reviewed:
- **`chat_screen` fixes:** reverse message ordering (backend is NEWEST-first, UI assumes oldest-first); **restore the typed text + reply on send failure** (data-loss bug, `chat_screen.dart:158/166` clear pre-await with no rollback); switch pagination from `before`-cursor to `offset`.
- **Hide unbuilt features** (endpoints the backend lacks): media (image/video/voice), stickers, edit, delete, pin/mute, typing/realtime UI — hide their entry points so nothing shows broken.
- **Polling:** poll `GET …/messages` while a thread is open + refresh the conversation list on a slower interval (REST stand-in for realtime).
- **Re-enable the Chat tab** in `main_shell.dart` (revert the Phase 5 removal) — pair this with the backend deploy so chat only appears once it works against prod.
- **createConversation wiring:** call it from the "message" affordance on a profile/match to start a chat.

## Self-Review

**Coverage:** data-layer contract reconciliation (Message + ChatService) → Tasks 1-2, unit-tested with
canned/mock responses (no live backend needed). Screen/hide/polling/tab explicitly deferred to FE-1b/go-live. ✅
**Placeholders:** none — deltas are concrete; the one open detail (ReplyTo's exact API for the scalar-id
case) is bounded and resolved by reading the model, not a TBD. ✅
**Consistency:** field names match the backend MSG/CONVERSATION contract above; `ChatService(apiClient:)`
injection matches the ApiClient.testInstance pattern already in the repo. ✅
