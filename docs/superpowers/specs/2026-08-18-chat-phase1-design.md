# Chat — Phase 1: State Ownership, Pagination, Decomposition

Design for the first of three sub-projects. The other two — app-wide render and
image performance, then Discover — get their own specs and are named here only
where this one constrains them.

Spans two repositories: the app (`flame`) and the backend
(`language_exchange_backend_application/flame`).

## Why

Every chat defect found while surveying the surface traces back to one cause:
the open thread's messages are owned by both `_ChatScreenState._messages` and
`conversationsProvider`'s `Conversation.messages`, and the two are reconciled
inside `build()`.

`lib/screens/chat/chat_screen.dart:1019-1031`:

```dart
for (final msg in currentConversation.messages) {
  if (!_messages.any((m) => m.id == msg.id)) {
    WidgetsBinding.instance.addPostFrameCallback((_) { ... });
    break; // Only add one at a time to avoid multiple setState calls
  }
}
```

That is an O(n·m) id scan on every rebuild, feeding a post-frame `setState` that
admits one message per frame. Six `setState` paths in the same class can trigger
it. The `break` and its comment are the shape of the problem, not a bug to patch.

The screen is 1437 lines and ~45 methods holding message list, pagination,
typing, presence, pinning, mute, voice recording, attachments, reactions,
editing and deletion.

## Deliberately not in this phase

- **Feature ports from BananaTalk** — forward, multi-select, bookmarks, per-chat
  wallpaper, phrases panel, GIF picker, failed-message retry. Phase 2.
- **Composer drafts** (`ChatDraftService`). Phase 2.
- **Thread caching across navigation.** See "Lifecycle" below — stated as a
  non-goal rather than left ambiguous.
- **The other ~180 hardcoded colours outside `lib/screens/chat`.** Belongs to the
  app-wide sub-project.
- **Discover's offset-pagination bug**, which is the same defect class in
  `discovery_provider.dart`. Third sub-project, and it should reuse whatever
  cursor convention this phase establishes.

## Architecture

### `messageThread` owns the open thread

```dart
class MessageThreadState {
  final List<Message> messages;   // oldest-first, display order
  final List<ChatRow> rows;       // memoized; recomputed only when messages change
  final String? oldestId;         // cursor for the next page
  final bool hasMore;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final String? error;
}

final messageThreadProvider = StateNotifierProvider.autoDispose
    .family<MessageThreadNotifier, MessageThreadState, String>(...);
```

The notifier owns initial load, paging, and its own subscription to
`RealtimeConnection`'s `messageNew` / `messageEdited` / `messageDeleted`
streams, filtered to its own `conversationId`.

**Lifecycle.** `autoDispose` without `keepAlive`. Leaving the chat drops the
thread and cancels the subscription. Re-entering refetches — which is current
behaviour, so no regression, but it means this approach does not buy instant
re-entry. Memory stays bounded instead of accumulating one thread per
conversation visited. An LRU cache is a later decision with its own evidence.

### `Conversation.messages` becomes `Conversation.lastMessage`

The load-bearing change. `matches_screen.dart:464,477` render only
`conversation.lastMessagePreview` and `conversation.lastMessage?.timeText` — the
list surface never reads any other element. Holding the full list bought nothing
and cost three defects:

1. It was the second half of the duplicated state.
2. `addMessageToConversation` (`chat_provider.dart:336-352`) appends to it on
   every socket push, for every conversation, for the whole session, and nothing
   ever trims it.
3. `markAsRead` (`chat_provider.dart:317-330`) maps a `copyWith` over every
   message in it to set a status only the last element displays.

`lastMessagePreview` and `timeText` keep their current behaviour, sourced from
`lastMessage`. `addMessageToConversation` becomes: replace `lastMessage`, bump
`lastMessageAt`, increment `unreadCount`. No list, no `any()` scan.

With both changes in place the reconciliation loop has nothing to reconcile and
is deleted, along with the post-frame drip and the one-at-a-time `break`.

### Division of responsibility

Stated so it cannot drift:

- `conversationsProvider` owns list previews, unread counts, mute, pin, archive.
  Never thread bodies.
- `messageThread` owns thread bodies. Never unread counts.

Both subscribe to the same pushes and touch disjoint slices, so neither depends
on the other's ordering. One cross-call remains: on a push into the open thread,
`messageThread` calls `conversationsProvider.clearUnread`.

## Pagination

### Backend: a `before` cursor

`services/chatService.js:245-252` is today:

```js
const total = await Message.countDocuments(filter);
const msgs = await Message.find(filter).sort({ createdAt: -1 }).skip(offset).limit(limit);
```

`GET /conversations/:id/messages` gains `before=<messageId>`:

- Keyset instead of skip — filter gains `_id: { $lt: ObjectId(before) }`, sort
  `{ _id: -1 }`. A message arriving mid-scroll cannot shift a window anchored to
  an id.
- `has_more` from fetching `limit + 1` and checking for the extra, replacing the
  per-page `countDocuments`.
- Deep history stops paying Mongo's `skip(offset)` cost.

**Back-compatibility.** `offset` keeps working and the `offset` path still
returns `total`, for installed clients. `before` and `offset` are mutually
exclusive; if both arrive, `before` wins. This follows the precedent set when the
refresh route was taught to accept both casings rather than inventing a second
convention.

### App

- `oldestId` replaces `offset: _messages.length` (`chat_screen.dart:181`), which
  drifted because socket pushes inflate `_messages.length` between pages. The
  existing `existingIds` dedupe hid the resulting overlap by dropping it; the
  gap on the other side was real and silent.
- `_onScroll`'s exact float equality (`chat_screen.dart:145`,
  `pixels == minScrollExtent`) becomes a threshold comparison. Under iOS bounce
  physics `pixels` goes negative on overscroll, so the equality is transient at
  best and load-more often never fires.

### Also in this contract

`socket/flameSocket.js`'s `emitRead` has no production caller — only
`__tests__/blockEnforcement.test.js` — and its payload `{ conversation_id }`
omits the `by` field `FlameSocketService._handleRead`
(`flame_socket_service.dart:169-181`) requires, so it would be dropped on arrival
even if it were wired. Delete it. The socket `markRead` relay already covers the
only case where a receipt is visible to anyone.

## Decomposition

`lib/screens/chat/`:

```
conversation/chat_screen.dart          orchestrator only, ~200 lines
conversation/handlers/
  composer_actions.dart                send text, sticker, media, voice
  message_actions.dart                 edit, delete, react, pin, unpin, reply
  thread_actions.dart                  mute, mark read, load/pin/unpin pinned
message/messages_list.dart             StatelessWidget, ValueKey per row
message/message_bubble.dart
message/chat_rows.dart
message/date_separator_chip.dart
message/conversation_empty_state.dart
header/chat_app_bar.dart
header/pinned_messages_bar.dart
input/chat_input.dart                  (exists)
panels/sticker_panel.dart              (exists)
dialogs/message_actions_sheet.dart
error/chat_error_widget.dart
widgets/chat_snackbar.dart
state/message_thread_provider.dart
state/thread_presence_provider.dart
```

Every current method has a destination:

| Current | Destination |
|---|---|
| `_loadInitialMessages`, `_loadMoreMessages`, `_refreshMessages`, `_onScroll` | `state/message_thread_provider.dart` |
| `_connectFlameSocket`, `_onSocketMessage{New,Edited,Deleted}`, `_replaceMessage` | `state/message_thread_provider.dart` |
| `_onSocketTyping/StopTyping`, `_onSocketPresence/PresenceBulk`, `_onMessageTextChanged`, `_stopTypingNow` | `state/thread_presence_provider.dart` |
| `_startPolling`, `_pollForNewMessages`, `_pollInterval` | deleted |
| `_sendMessage`, `_sendSticker`, `_openStickerPanel`, `_start/_stop/_cancel/_sendRecording`, `_openAttachmentSheet` | `handlers/composer_actions.dart` |
| `_onMessageLongPress`, `_addReaction`, `_editMessage`, `_showDeleteOptions`, `_deleteMessage` | `handlers/message_actions.dart` |
| `_loadPinned`, `_pin`, `_unpin`, `_toggleMute`, `_markMessagesAsRead` | `handlers/thread_actions.dart` |
| `_buildAppBar` | `header/chat_app_bar.dart` |
| `_PinnedMessagesBar` | `header/pinned_messages_bar.dart` |
| `_buildMessageList` | `message/messages_list.dart` |
| `_buildEmptyChat` | `message/conversation_empty_state.dart` |
| `_DateSeparatorChip` | `message/date_separator_chip.dart` |
| `_MessageActionsSheet` | `dialogs/message_actions_sheet.dart` |
| `_showError` | `widgets/chat_snackbar.dart` |
| `_scrollToBottom`, `_isScrolledToBottom`, `_jumpToMessage` | stay — they own the `ScrollController` |

`thread_presence_provider.dart` takes the two timers, `_isTyping`,
`_isOtherUserTypingFlame` and the `_presence` map out of the screen.

**Handler shape**, following
`bananatalk_app/lib/pages/chat/conversation/handlers/message_action_handlers.dart`
— free functions, everything by named parameter, no hidden state, callable
directly from a test:

```dart
Future<void> handleEditMessage({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required Message message,
}) async { ... }
```

If the orchestrator exceeds 250 lines, a section went to the wrong file.

### Two deletions

**Polling is dead, not disabled.** `realtimeEnabled` is `true` in both shipped
presets (`env.dart:112,123`), so the 4-second `Timer.periodic` created for every
open chat (`chat_screen.dart:241-247`) has never once called
`_pollForNewMessages` in local or prod. Its doc comment — *"only runs when
`realtimeEnabled` is false (which is always, for now, since the backend has no
chat socket)"* — describes a world that ended when `flameSocket.js` shipped.

**`widgets/sticker_picker.dart` is unreachable.** 675 lines, exported by
`widgets/widgets.dart` but with no use of `StickerPicker` anywhere in `lib/` or
`test/`. It was written against a sticker pack catalog with hosted artwork that
was cut; the 103-line emoji-only `sticker_panel.dart` replaced it. It also holds
34 of chat's 120 hardcoded colours. Delete the file and the barrel export.

## Render performance

1. **`ValueKey(message.id)` on every row.** Absent today
   (`chat_screen.dart:1227`), so Flutter reuses element and `State` across
   different messages whenever the list shifts.
2. **Hoist the per-bubble closure.** `onLongPress: () => _onMessageLongPress(message)`
   is a fresh closure per bubble per build. The list takes one
   `void Function(Message)`.
3. **Rows move into the notifier.** `buildChatRows`'s `now` parameter is never
   read in its body — the labelling is all in the separate `chatDayLabel(day, now)`,
   called at render time by the separator chip. Its docstring claims `now` is
   what keeps label tests stable; that is `chatDayLabel`'s doing. Dart does not
   flag unused parameters, so the analyzer stayed quiet. Dropping it makes
   `buildChatRows(messages)` a pure function of an immutable list, so it can live
   in `MessageThreadState` and recompute only when messages change.
   `chatDayLabel(day, now)` stays at render time, so "Today"/"Yesterday" still
   update across midnight.
4. **Downscale avatars.** Only `message_bubble.dart:569` passes `memCacheWidth`
   today. A `toAvatarProvider(diameter, dpr)` helper makes it impossible to hand
   a 40px `CircleAvatar` a full-resolution decode — the app bar, matches list and
   typing indicator all currently do.
5. **`keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag`** on the
   message list.
6. **Stop refetching after a successful send.** `_sendMessage` awaits
   `_refreshMessages()` on success (`chat_screen.dart:549`), a full newest-page
   fetch, even though `POST /conversations/:id/messages` already returns the
   created message in `data`. `conversationsProvider.sendMessage` returns only
   `String? error` and discards it. Return the message and append it.

### Dark mode sweep

Chat holds 120 hardcoded colours across 10 files (67 `Colors.grey`, 23
`Colors.white`, then `black87`/`white70`/`white54`/`blue`/`amber`). Deleting
`sticker_picker.dart` removes 34. The remaining ~86 are replaced with semantic
tokens as each file moves, so the ten files are touched once rather than twice.
This closes the gap the profile follow-ups doc recorded: *"Dark mode will look
inconsistent between the profile tab and the chat tab until that sweep happens."*

### Localization gap

`chatDayLabel` hardcodes English `'Today'`, `'Yesterday'` and `'Jan'`…`'Dec'` in
an app with 13 locales and a working ARB pipeline. It is new code that skipped
l10n. Folded into this phase because it lives in the files being moved.

## Error handling

**Three render states, never collapsed.** Today a failed initial load leaves
`_messages` empty and renders `_buildEmptyChat()`, so a network failure is
indistinguishable from an empty conversation and the user is invited to "say hi"
to a thread that failed to load. This is the defect the profile follow-ups doc
recorded in `settings_screen` — `valueOrNull ?? true` collapsing loading and
error — reappearing in chat.

`MessageThreadState.error` is therefore first-class, and `ChatMessagesList`
branches on all three: spinner, `ChatErrorWidget(error:, onRetry:)`, or
`ConversationEmptyState`. `EditProfileScreen`'s full `when(...)` is the pattern
to match, not `settings_screen`'s.

| Failure | Behaviour |
|---|---|
| Initial load | Full-surface error with retry. Never the empty state. |
| Load more | Keep every message on screen, inline retry at the top, and **do not advance `oldestId`** — advancing past a page that never arrived loses history silently. |
| Send | Unchanged; already restores composer text and reply target (`chat_screen.dart:552-560`). |
| Send success | Append the returned message. No refetch. |
| Malformed push | Already caught and logged per-handler in `FlameSocketService`. |
| `AUTH_LOST` mid-action | `ApiClient.onAuthLost` already routes to login. Nothing chat-specific. |

All user-facing strings go through `ErrorStringsFor` and the ARB files, never raw
backend text.

## Testing

The bar is set by this repo's own recorded lesson: per-task tests passed over two
defects that only a whole-branch review caught. So each test below is named for
the bug it would have caught.

**`MessageThreadNotifier`**
- A socket push arriving mid-paging does not change the next page's cursor — *the
  offset-drift test.*
- Initial-load failure sets `error`, and `error` is distinct from empty — *the
  loading/error-collapse test.*
- Load-more failure keeps existing messages and does not advance `oldestId`.
- Load-more prepends older messages and advances `oldestId`.
- A push for a different conversation is ignored.
- Dispose cancels the socket subscription.
- `rows` recompute only when `messages` changes identity.

**Backend `__tests__/`**
- `before` returns strictly older messages.
- A message inserted between page 1 and page 2 produces neither a gap nor a
  duplicate — *the drift test, server side.*
- The `offset` path still works and still returns `total`.
- `before` wins when both are sent.

**Model**
- `Conversation.lastMessage` replaces `messages`, with `lastMessagePreview` and
  `timeText` unchanged, in both casings.
- `addMessageToConversation` bumps unread and replaces `lastMessage` without
  retaining a list.
- `markAsRead` no longer maps over a message list.

**Handlers** — called directly as free functions with a fake `ref`, no widget
pumping.

**Widgets** — `ChatMessagesList` emits `ValueKey(message.id)` per row; each of
the three states renders its own widget.

**Theme gate** — extend `test/theme/profile_settings_theme_test.dart` to
`lib/screens/chat` and widen its regex past `white|black|grey|…` so
`Colors.blue`/`Colors.amber` cannot pass. Add token-resolution assertions in the
manner of `app_tokens_test.dart`'s `fill != surface`: the profile lesson was that
banning literals proves nothing about what the replacement resolves to.

**Verification gate** — `flutter analyze` at 0 errors and 0 warnings, full
`flutter test` green, and the backend's `node --test` green. Both repositories,
since this phase spans them.

## Sources

- `bananatalk_app/lib/pages/chat/` — directory layout, `ChatMessagesList` as a
  `StatelessWidget` with per-row `ValueKey`, `keyboardDismissBehavior`,
  `buildChatRows(messages)` without an injected clock, `ChatErrorWidget`,
  `showChatSnackBar`.
- `bananatalk_app/lib/pages/chat/conversation/handlers/message_action_handlers.dart`
  — the free-function handler pattern.

Not taken from there: its own `chat_conversation_screen.dart` is 1961 lines, so
it has not finished this job either, and its `messages_list.dart` does an O(n)
`messages.firstWhere` per item inside `itemBuilder`.
