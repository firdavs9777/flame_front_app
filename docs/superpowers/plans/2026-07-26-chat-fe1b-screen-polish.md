# Chat-FE-1b — Screen Polish, Hide-Unbuilt, Polling, Tab Re-enable

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Checkbox steps.

**Goal:** Finish the frontend chat so it's usable and honest: fix the send data-loss + message ordering, hide the features the backend doesn't have, add polling, and re-enable the Chat tab behind a flag (on for local dev, off for prod until the backend deploys).

**Builds on:** Chat-FE-1 (data layer done — `Message.fromJson` + `ChatService` reconciled + mock-tested). Backend live on `feat/flame-chat` (run locally to test).

## Global Constraints

- Frontend repo `~/Desktop/Flame/flame_front_app`. Backend not deployed → prod keeps chat hidden (flag off); local dev turns it on.
- Preserve the committed realtime guard + StoryTray.
- Screen/widget changes: verify with `flutter analyze` + `flutter test` (full suite stays green) + review. Unit-test where a pure seam exists; otherwise analyze + review are the gate (document why).
- Commands: `flutter test`, `flutter analyze <paths>`.

---

### Task 1: `chatEnabled` flag + re-enable the Chat tab

**Files:** Modify `lib/config/env.dart`, `lib/screens/main_shell.dart`; Test `test/config/env_flags_test.dart` (extend).

- [ ] **Step 1:** In `lib/config/env.dart`, add a `final bool chatEnabled;` field to `EnvConfig` + constructor (default `false`). Set `chatEnabled: true` in `_local` and leave `_prod` at the default `false` (chat hidden in prod until the backend deploys).
- [ ] **Step 2:** Extend `test/config/env_flags_test.dart` with: `expect(EnvConfig.current.chatEnabled, isFalse);` (default/prod env in tests). Run → it should pass once the field exists (RED is the compile error before adding the field).
- [ ] **Step 3:** In `lib/screens/main_shell.dart`, re-add the Chat tab **conditionally on `EnvConfig.current.chatEnabled`**. Because Phase 5 removed it, reintroduce it so that when the flag is on the tabs are Discover/Chat/Profile/Settings (4) and when off they stay Discover/Profile/Settings (3). Implement by building the screen list + nav items from the flag:
  - `_screens`: `[HomeScreen(), if (EnvConfig.current.chatEnabled) MatchesScreen(), MyProfileScreen(), SettingsScreen()]`.
  - Re-import `chat/matches_screen.dart`.
  - In `_initializeData`, when chatEnabled, also load conversations (guard the chat provider reads behind the flag).
  - In `_FlameNavBar`, insert the Chat `_NavItem` (icon `Icons.chat_bubble_outline`/`chat_bubble`, label `context.l10n.navChat`) at index 1 when the flag is on, and renumber the remaining `onTap` indices so they stay contiguous and match `_screens` order. Keep it clean — the indices MUST match `_screens`.
- [ ] **Step 4:** `flutter analyze lib/config/env.dart lib/screens/main_shell.dart` clean; `flutter test test/config/env_flags_test.dart` pass.
- [ ] **Step 5:** Commit `lib/config/env.dart lib/screens/main_shell.dart test/config/env_flags_test.dart` — `feat(chat): re-enable Chat tab behind EnvConfig.chatEnabled (on for local, off for prod)`.

---

### Task 2: Fix send data-loss + message display ordering

**Files:** Modify `lib/screens/chat/chat_screen.dart` (READ it first).

**Send data-loss (`_sendMessage`, ~L153-185):** capture `content` (and the current `_replyingTo`) into locals; on the service call FAILURE, RESTORE `_messageController.text = content` and `_replyingTo` (don't leave the box empty on error). The input should only stay cleared on success.

**Display ordering:** the backend returns messages **newest-first**; the UI renders `_messages` top→bottom expecting **oldest-first** (newest at bottom, `_scrollToBottom` → maxScrollExtent). After fetching a page, **reverse it** so the in-memory `_messages` is oldest→newest. For "load older" pagination, switch from the `before`-cursor to **offset** (page size × loaded count), reverse each fetched page, and **prepend** older pages to the top (preserving scroll). Keep `_onScroll` triggering the load at the top (`minScrollExtent`).

- [ ] **Step 1:** Read `chat_screen.dart`; implement the send-failure restore and the ordering/offset changes described above. (Also update the provider/`getMessages` call to pass `offset` instead of `before` — the service now takes `offset`.)
- [ ] **Step 2:** `flutter analyze lib/screens/chat/chat_screen.dart` clean; `flutter test` full suite green.
- [ ] **Step 3:** Commit — `fix(chat): restore input on send failure; render newest-at-bottom with offset paging`.

> No unit test: this is `StatefulWidget` scroll/controller behavior that isn't cleanly unit-testable here; verified by analyze + full suite + review, and manual local run against the backend.

---

### Task 3: Hide unbuilt-feature entry points

**Files:** Modify `lib/screens/chat/chat_screen.dart` (and the chat widgets it uses).

The backend supports **text only**. Hide the UI entry points for everything it can't do so nothing appears broken: the attachment/media button + voice recorder (~L189-323, L541-551), the sticker button/picker (~L325-358), the edit and delete message actions in the long-press sheet (~L385-392, L405-471), and any typing-indicator send UI (~L132-151, L516, L539-540). Prefer removing/`if(false)`-gating the buttons over leaving dead taps. Keep the text input, send, reply, and reaction (add) affordances.

- [ ] **Step 1:** Read the file; remove or gate those entry points. Keep reply + add-reaction (both backed). Ensure no now-unused imports/vars trip analyze.
- [ ] **Step 2:** `flutter analyze` clean on touched files; `flutter test` green.
- [ ] **Step 3:** Commit — `feat(chat): hide unbuilt features (media/stickers/edit/delete/typing) for text-only MVP`.

---

### Task 4: Poll for new messages

**Files:** Modify `lib/screens/chat/chat_screen.dart` (thread) and/or `lib/providers/chat_provider.dart`.

Add a lightweight `Timer.periodic` (e.g. 4s) while a chat thread is open that re-fetches the latest messages (and marks read), and a slower refresh of the conversation list on the matches screen. Cancel timers in `dispose`. This is the REST stand-in for realtime; it must respect `EnvConfig.realtimeEnabled` (only poll when realtime is off, which is always for now).

- [ ] **Step 1:** Implement the polling timer + cancellation. De-dupe fetched messages by id (don't duplicate on each poll).
- [ ] **Step 2:** `flutter analyze` clean; `flutter test` green.
- [ ] **Step 3:** Commit — `feat(chat): poll for new messages while a thread is open`.

---

### Task 5: Verification + overview

- [ ] `flutter test` full suite green; `flutter analyze` no new issues in touched files.
- [ ] Update `docs/PROJECT_OVERVIEW.md` to reflect: chat backend built (feat/flame-chat, not deployed), frontend wired + tab behind `chatEnabled`, and the remaining go-live steps (deploy backend + `pm2 restart`, flip prod `chatEnabled`). Commit.

---

## Deferred to go-live (NOT here)
- Deploy `feat/flame-chat` to prod (merge + `pm2 restart language` + smoke), then flip `_prod.chatEnabled = true`.
- Realtime (Socket.IO) — replaces polling.
- Media messages — after the Spaces fix.
- Reactions/reply UI polish (FE-2) beyond what's already wired.

## Self-Review
Coverage: send-restore + ordering (Task 2), hide-unbuilt (Task 3), polling (Task 4), tab behind flag (Task 1),
overview (Task 5). ✅ Screen-level tasks are analyze+review-gated (documented). Flag keeps prod honest while
enabling local testing. ✅
