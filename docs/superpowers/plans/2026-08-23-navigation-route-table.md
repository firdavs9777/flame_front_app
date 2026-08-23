# Navigation Route Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans.

**Goal:** Give every destination a name and typed arguments, reachable from
outside the widget tree, so a push notification can open a specific conversation.

**Architecture:** `onGenerateRoute` over a constant name table with one argument
class per parameterised destination. `MainShell`, `home:` and the auth gating are
untouched — the socket lifecycle lives there. Route names and argument types are
shaped to survive a later go_router swap.

**Tech Stack:** Flutter 3.38, Riverpod, flutter_gen l10n (13 locales); backend
Node/Express/Mongoose with node:test + supertest.

**Spec:** `docs/superpowers/specs/2026-08-23-navigation-route-table-design.md`

## Global Constraints

- No new dependencies.
- `main_shell.dart`'s lifecycle code (`onTokenRefreshed`, `didChangeAppLifecycleState`,
  `_initializeData`) must not change. A broken socket stops chat delivery silently.
- All 13 locales for every new key: en, ko, ja, zh, es, fr, de, ru, pt, pt_BR, id, tr, and the template.
- Reuse an existing ARB key when one already carries the same text.
- `flutter analyze` must stay at 0 errors / 0 warnings.
- Backend `main` auto-deploys on push.

---

### Task 1: Route names and argument types

**Files:**
- Create: `lib/core/navigation/app_routes.dart`
- Test: `test/core/navigation/app_routes_test.dart`

**Interfaces:**
- Produces: `AppRoutes` (14 string constants), `ChatRouteArgs.conversation(Conversation)`,
  `ChatRouteArgs.id(String)`, `ProfileDetailArgs({user, isPreview})`,
  `MediaViewerArgs({url, heroTag})`, `StoryViewerArgs({users, initialUserIndex})`,
  and `AppRoutes.all` — the enumerated name list Task 2's test iterates.

- [ ] **Step 1: Write the failing test** — every constant appears in `AppRoutes.all`
      (so a name cannot be added without the router test seeing it); `ChatRouteArgs`
      exposes exactly one of conversation/id per constructor.
- [ ] **Step 2: Run it, expect a compile failure** (`AppRoutes` not found).
- [ ] **Step 3: Write `app_routes.dart`** per the spec's listing.
- [ ] **Step 4: Run the test, expect pass.**
- [ ] **Step 5: Commit.**

### Task 2: The router

**Files:**
- Create: `lib/core/navigation/app_router.dart`
- Modify: `lib/main.dart` (swap the one-entry `routes:` map for `onGenerateRoute`, add `navigatorKey`)
- Test: `test/core/navigation/app_router_test.dart`

**Interfaces:**
- Consumes: everything from Task 1.
- Produces: `AppRouter.onGenerateRoute(RouteSettings)`, `appNavigatorKey`.

- [ ] **Step 1: Write the failing tests** — each name in `AppRoutes.all` resolves
      to a non-null route; an unknown name resolves to the fallback rather than
      throwing; each argument class lands on its screen; a wrong argument type
      yields the fallback instead of a cast error.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.** Closure-taking destinations (`ChatSearchScreen`,
      `ArchivedConversationsScreen`) build their closure inside a `Consumer` in
      the route case. `/discover/filters` keeps its existing string exactly.
- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit.**

### Task 3: Backend — GET /conversations/:id

**Files:**
- Modify: `flame/services/chatService.js`, `flame/controllers/chatController.js`, `flame/routes/conversations.js`
- Test: `flame/__tests__/conversationById.test.js`

**Interfaces:**
- Produces: `chatService.getConversation(userId, conversationId)` returning the
  same shape as one `listConversations` row; throws `NotFoundError` for a
  non-participant, a blocked pair, or an ended match.

- [ ] **Step 1: Write the failing test** — participant gets it; non-participant
      404s (not 403, so ids cannot be probed); blocked pair unreachable; ended
      match unreachable. Mirror `blockEnforcement.test.js`'s cache-clear list.
- [ ] **Step 2: Run, expect failure** (route absent → 404 for everyone, so assert
      the participant's 200 first).
- [ ] **Step 3: Implement**, reusing the list row's shaping function rather than
      writing a second serialiser.
- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit.**

### Task 4: App — resolve a chat from an id

**Files:**
- Modify: `lib/services/chat_service.dart` (add `getConversation(String id)`)
- Create: `lib/core/navigation/chat_route_resolver.dart`
- Test: `test/core/navigation/chat_route_resolver_test.dart`

- [ ] **Step 1: Write the failing tests** — `ChatRouteArgs.conversation` builds
      `ChatScreen` with no fetch; `.id` found in the loaded list builds it with no
      fetch; `.id` absent from the list fetches; a failed fetch renders a localized
      error with a retry.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, expect pass.**
- [ ] **Step 5: Commit.**

### Task 5: Convert the 16 call sites

**Files (all Modify):**
- `lib/screens/settings/settings_screen.dart` (3: blocked, notifications, language)
- `lib/screens/profile/my_profile_screen.dart` (3: settings, edit, profile preview)
- `lib/screens/chat/matches_screen.dart` (4: search, archived, chat ×2)
- `lib/screens/chat/conversation/chat_screen.dart` (1: profile detail)
- `lib/screens/chat/widgets/message_bubble.dart` (1: media viewer)
- `lib/screens/discover/discover_screen.dart` (1: profile detail)
- `lib/screens/stories/widgets/story_tray.dart` (2: story viewer, create story)
- `lib/screens/auth/login_screen.dart` (1: forgot password)
- Test: `test/core/navigation/single_navigation_path_test.dart`

- [ ] **Step 1: Write the failing source-level test** — no file under
      `lib/screens` contains `MaterialPageRoute`.
- [ ] **Step 2: Run, expect failure listing all 9 files.**
- [ ] **Step 3: Convert each call site**, one file at a time, running that file's
      existing tests after each. `isPreview: true` in `my_profile_screen.dart` must
      survive — it is the one argument whose loss shows a user their own
      like/pass buttons.
- [ ] **Step 4: Run the source test plus the full suite, expect pass.**
- [ ] **Step 5: Commit.**

### Task 6: The Chat tab's strings

**Files:**
- Modify: `lib/screens/chat/matches_screen.dart` (7), `lib/screens/chat/archived_conversations_screen.dart` (2), `lib/screens/chat/chat_search_screen.dart` (1)
- Modify: all 13 `lib/l10n/app_*.arb`
- Modify: `lib/screens/main_shell.dart` (the stale "Profile, Settings" comment only)
- Test: `test/screens/chat/chat_tab_l10n_test.dart`

- [ ] **Step 1: Write the failing source-level test** — no `Text('...')` literal
      in the three screens.
- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Grep the ARBs for existing keys** covering Retry/Cancel/Error
      before adding any. Add only what is genuinely new, in all 13 locales.
- [ ] **Step 4: Replace the literals; regenerate l10n; fix the stale comment.**
- [ ] **Step 5: Run the test plus the full suite, expect pass.**
- [ ] **Step 6: Commit.**

### Task 7: Verification

- [ ] **Step 1:** `flutter analyze` — 0 errors, 0 warnings.
- [ ] **Step 2:** `flutter test` — full suite green.
- [ ] **Step 3:** Backend sweep by exit code, per suite. Re-run any failure
      individually before believing it: this suite is flaky under sequential load
      (`messageSearch` and `conversationControls` both failed a sweep and passed
      alone).
- [ ] **Step 4:** Grep for leftovers — `MaterialPageRoute` outside the router,
      `Navigator.push(` with a builder, hardcoded strings in the chat screens.
- [ ] **Step 5:** Report. State plainly that no device walkthrough has happened.
