# Navigation: a route table, and the Chat tab's last English strings

**Date:** 2026-08-23
**Status:** approved
**Scope:** app (`flame`) + one backend endpoint

## Why

Push notifications are the next phase. A notification tap fires **outside the
widget tree** and carries a conversation **id**, and it has to land on that
conversation. Today the app cannot do either half of that:

- 16 of 18 navigations are imperative `MaterialPageRoute` pushes. There is one
  named route (`/discover/filters`). A destination that only exists as a
  closure inside a widget's `onTap` cannot be named by anything outside it.
- There is no `navigatorKey`, so nothing outside the tree has a navigator.
- `ChatScreen` takes `required Conversation conversation`. Nothing can turn an
  id into a `Conversation`: `ChatService` has no single fetch, and the backend
  has no `GET /conversations/:id` — only the paginated list.

The last point is why this spec includes a backend endpoint. Resolving an id
against the already-loaded list looks sufficient and is not: the list is
paginated, so a notification about any older conversation would resolve to
nothing and the tap would do nothing. That is the exact failure a user reports
as "notifications don't work".

## What this is NOT

**Not go_router.** The approved option named it; closer reading changed the
recommendation. `MainShell` owns the socket's token-refresh hook (keyed on
`initState`/`dispose` identity), the app-lifecycle resume that rebuilds the
socket, and the initial data load. `main.dart` gates auth through `home:` with a
conditional widget, not a redirect. go_router converts both — `home:` into a
router redirect, `MainShell` into a `StatefulShellRoute` — which is precisely
where the socket lifecycle lives, and a broken socket means chat silently stops
delivering. Not the thing to destabilise before a release, for a mechanism whose
extra value (URL-based universal/app links) nothing in this phase uses.

Route names and argument types are designed to survive that swap unchanged, so
Stage 2 stays open.

**Not an IA change.** Three tabs stay three tabs. The Chat tab keeps stories,
new matches and conversations in one scroll — decided explicitly, revisit on
usage data.

**Not a Likes tab.** No backend exists for "who liked you" (no likes/admirers
routes at all). It needs a monetisation decision, and a fourth tab that cannot
be filled is worse than three that work. Post-launch.

## Design

### 1. Route names and typed arguments

`lib/core/navigation/app_routes.dart` — name constants and one argument class
per destination that takes parameters. Arguments are classes, not maps, so a
wrong shape fails at compile time rather than as a runtime cast.

```dart
abstract final class AppRoutes {
  static const discoverFilters = '/discover/filters';
  static const settings = '/settings';
  static const notificationSettings = '/settings/notifications';
  static const language = '/settings/language';
  static const blockedUsers = '/settings/blocked';
  static const editProfile = '/profile/edit';
  static const profileDetail = '/profile/detail';
  static const chat = '/chat';
  static const chatSearch = '/chat/search';
  static const archivedConversations = '/chat/archived';
  static const mediaViewer = '/media';
  static const storyViewer = '/stories/view';
  static const createStory = '/stories/create';
  static const forgotPassword = '/auth/forgot-password';
}
```

`ChatRouteArgs` carries **either** a resolved conversation or an id:

```dart
class ChatRouteArgs {
  const ChatRouteArgs.conversation(Conversation this.conversation) : id = null;
  const ChatRouteArgs.id(String this.id) : conversation = null;
  final Conversation? conversation;
  final String? id;
}
```

Two constructors rather than one nullable pair: the list already holds the
conversation and must not pay for a fetch, while a notification only ever has
an id. Both cases are real and neither should be able to pass both or neither.

`ProfileDetailArgs {User user, bool isPreview}`,
`MediaViewerArgs {String url, String heroTag}`,
`StoryViewerArgs {List<UserStories> users, int initialUserIndex}`.

### 2. The router

`lib/core/navigation/app_router.dart` — one `onGenerateRoute` mapping every
name. Unknown names return a route rendering a localized "screen not found"
rather than throwing, because a stale notification payload is a normal event and
must not crash the app.

Two destinations take **closures**, not data: `ChatSearchScreen(search:)` and
`ArchivedConversationsScreen(load:)` are handed functions that capture `ref`.
Their route builders wrap the screen in a `Consumer` and construct the closure
there. This moves the wiring from the call site into the route table — a small
improvement, since that closure is duplicated per call site today.

### 3. Resolving a chat from an id

`ChatRouteArgs.id` renders a resolver that:
1. checks the loaded conversation list first (the common case: app was open),
2. falls back to `GET /conversations/:id`,
3. shows a spinner while resolving and a localized error with a retry if it
   fails.

`ChatRouteArgs.conversation` skips all of that and builds `ChatScreen` directly,
so the existing paths are unchanged in behaviour and cost.

### 4. Backend: `GET /conversations/:id`

Returns one conversation in the same shape as a list item. Same authorisation as
every other conversation route: participant only, and it must honour blocks and
ended matches — a conversation that has dropped out of the list must not be
reachable by id. 404 rather than 403 for a non-participant, matching
`matchService.unmatch`, so ids cannot be probed.

### 5. Navigator key

`GlobalKey<NavigatorState>` on `MaterialApp`, exposed so a notification handler
can navigate without a `BuildContext`. Nothing consumes it yet; it exists
because adding it later means touching `main.dart` again during the
notifications work.

### 6. The Chat tab's hardcoded strings

Ten English literals across three chat screens — this tab predates the
localization sweep that covered profile and settings, so it is the one tab that
does not translate:

- `matches_screen.dart` (7): `'Messages'`, `'Error loading matches: $error'`,
  `'Failed to load messages'`, `'Retry'`,
  `'Could not open this chat. Please try again.'`, `'Unmatch?'`, `'Cancel'`
- `archived_conversations_screen.dart` (2), `chat_search_screen.dart` (1)

All 13 locales. Reuse existing keys where one already says the same thing
(`Retry`, `Cancel` are near-certain duplicates) rather than adding synonyms.

### 7. One stale comment

`main_shell.dart:160` still reads "Discover, [Chat if enabled], Profile,
Settings". Settings stopped being a tab in Scope B. Left behind by me.

## Testing

- every name in `AppRoutes` resolves to a route — enumerated from the class, so
  adding a name without a case fails
- an unknown name renders the fallback rather than throwing
- each argument class round-trips through its route to the right screen
- wrong or missing arguments produce the fallback, not a cast error
- source-level: no widget under `lib/screens` constructs `MaterialPageRoute`
  (one way to navigate, matching `preference_ownership_test.dart`'s approach)
- source-level: no bare `Text('...')` literals left in the three chat screens
- backend: participant gets the conversation; non-participant 404s; a blocked
  pair and an ended match are both unreachable by id

## Risks

**The conversion is mechanical but wide** — 16 call sites across 9 files. The
source-level test is what makes it verifiable rather than hopeful.

**`isPreview` is a positional trap.** `ProfileDetailScreen(user:, isPreview:)`
defaults `isPreview` to false, and the preview path is one of three call sites.
Losing it would show a real user their own like/pass buttons. Its route case
carries a test.
