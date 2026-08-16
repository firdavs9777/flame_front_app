# Matching & Safety — Design

**Date:** 2026-08-16
**Phase:** A (of A → B). Phase B is chat enrichment, specified separately.
**Repos:** `~/Projects/BananaTalk/backend` (the `flame/` sub-app) and `~/Desktop/Flame/flame_front_app`

## Problem

Flame's swipe deck advances, but nothing happens. `POST /swipes/like` acknowledges
and persists nothing; `GET /matches` returns a hardcoded empty array; there is no
`Match` or `Swipe` model. The code says so:

```js
// Swipes aren't fully implemented server-side yet (no Swipe model / mutual-match
// detection). These acknowledge the action so the swipe deck advances instead of
// 404-ing. is_match is always false until real matching lands.
```

Consequences that look like separate bugs but share this one root cause:

- **Chat is unreachable.** It works — send, receive, edit, delete, reactions, read
  receipts, live socket — but no conversation can ever be created, so the Chat tab
  is permanently empty.
- **Discover repeats forever.** `discoveryService.discover` filters only on
  "not me" and "not deleted". With no swipe record there is nothing to exclude.
- **Report and block do nothing.** The app has complete UI and services calling
  `POST /reports`, `POST /blocks`, `DELETE /blocks/:userId`, `GET /blocks`. The
  backend has no such routes.
- **Stories are gated on matches** (`story_provider.dart`), so the feed is empty too.

**The app side is already built.** `matchesProvider`, `matchService.getMatches`,
`swipeProvider`, `addMatch()`, an "It's a Match!" dialog, the report/block menu —
all present and tested, all waiting for a server that never answers. Phase A is
therefore almost entirely backend work.

## Scope

**In:** like / pass / mutual match, super-like, unmatch, block, report, Discover
exclusion + basic filters.

**Out:** undo (route stays a no-op stub returning `{undone: false}`), Discover
ranking, and all of phase B.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Match rule | Strict mutual (Tinder-style) | Expected in dating apps; also produces the swipe data Discover needs |
| Conversation timing | Created with the match | Chat gets a guaranteed front door; match is immediately actionable |
| Discover ranking | Deferred | Exclusion and filters deliver most of the value; ranking is a separate phase |
| Storage | Collections for swipes/matches/reports, blocks embedded on User | See below |

## Data model

All on Flame's own mongoose connection (`flameConn`). BananaTalk is untouched.

### `Swipe` — new collection

```
from:      String   // who swiped
to:        String   // who was swiped on
action:    'like' | 'pass' | 'super'
createdAt: Date
```

- Unique compound index `(from, to)` — makes "already swiped?" an index hit and
  makes double-swipes impossible under a double-tap race.
- Index `(to, action)` — powers mutual detection and a future "who liked you".

Swipes are their **own collection, not embedded**: an active user generates
thousands, which would push the `User` document toward Mongo's 16MB ceiling and
turn "has A swiped B?" into an array scan.

### `Match` — new collection

```
users:          [String, String]   // ALWAYS stored sorted
conversationId: String
createdAt:      Date
endedBy:        String | null      // set on unmatch; never hard-deleted
```

Storing the pair **sorted** makes a match unique regardless of who swiped first: a
unique index on `users` then guarantees one match per pair, with no "did A match B
or B match A?" branching anywhere in the code.

### Blocks — embedded on `User`

Mirrors BananaTalk's proven shape:

```
blockedUsers: [{ user: String, blockedAt: Date }]
blockedBy:    [{ user: String, blockedAt: Date }]
```

Written as a pair in one operation. The redundancy is deliberate: blocks are
checked on **every** Discover query, match list, and message delivery, and the
bidirectional arrays make "hide people I blocked AND people who blocked me" a
single cheap check on a document already in hand.

### `Report` — new collection

BananaTalk's schema trimmed to Flame's needs:

```
reportedBy:   String
reportedUser: String
reason:       'inappropriate_content' | 'fake_profile' | 'harassment'
            | 'spam' | 'underage' | 'other'
description:  String (max 500)          // the app sends this as `details`
status:       'pending' | 'reviewed' | 'resolved' | 'dismissed'   // default pending
createdAt:    Date
```

The `reason` values are taken verbatim from the app's existing `ReportReason`
enum (`report_service.dart`), which already serialises to these exact strings —
the backend must accept them as-is rather than inventing its own vocabulary.

`status` is carried from day one, though unused, so a moderation queue can be
added later without a migration.

## Swipe → match → conversation

`POST /swipes/like` and `/swipes/super-like`:

1. Reject if either party has blocked the other, or the target is deleted.
2. Upsert the `Swipe` — idempotent, so retries and double-taps are harmless.
3. Look for the reciprocal `like`/`super` from `to` → `from`.
4. If found: create the `Match` and its `Conversation` together, return
   `{ is_match: true, match: {...} }`.
5. Otherwise: return `{ is_match: false, match: null }`.

Response shapes are **unchanged from the current stub**, so the app keeps working
as the backend gains behaviour.

**Concurrency.** If both users like each other simultaneously, the unique index on
`Match.users` lets exactly one insert win; the loser catches the duplicate-key
error (`11000`) and reads the winner's match. This mirrors the existing recovery in
`socialAuthService.findOrCreate`, so the codebase has one idiom for this.

**Super-like** counts as a like for matching, is flagged so the recipient can see
it, and decrements the quota already on `User` (`superLikesRemaining`,
`superLikesDay`), resetting daily.

**Unmatch** (`DELETE /matches/:id`) sets `endedBy` rather than deleting, preserving
swipe history so the unmatched person does not immediately reappear in Discover.

## Block enforcement

A block that only hides Discover is a broken block. Eight surfaces return other
users' data, so enforcement lives in one shared module rather than eight scattered
checks — `flame/services/visibilityService.js`:

- `excludedIdsFor(userId)` → ids to filter out (blocked + blockedBy, plus swiped
  where relevant), computed once per request.
- `assertCanInteract(a, b)` → throws `ForbiddenError` if either has blocked the other.

| Surface | Function | Enforcement |
|---|---|---|
| Discover deck | `discoveryService.discover` | exclude blocked, blockedBy, already-swiped |
| Matches | `GET /matches` | exclude blocked pairs and `endedBy` matches |
| Conversation list | `chatService.listConversations` | filter blocked participants |
| Open conversation | `chatService.openConversation` | `assertCanInteract` → 403 |
| Send message | `chatService.sendMessage` | `assertCanInteract` → 403 |
| Socket delivery | `flameSocket.emitNewMessage` | drop if blocked — a live socket must not bypass REST |
| Stories feed | `storyService.visibleAuthorFilter` | fold blocks into the existing filter |
| Profile view | `userService.getById` | 404, as if the user does not exist |

`storyService` already has a `visibleAuthorFilter`; the shared module generalises
that precedent instead of duplicating it.

**Blocking also unmatches** — sets `endedBy` and removes the conversation from both
lists, so a block is a complete severance.

The two easiest to miss are **socket delivery** and **stories**; both would leak a
blocked person straight back into view.

## API surface

Built to the contract the app **already calls**, so block/report need no app changes.

```
POST   /swipes/like        { user_id }  → { liked, is_match, match }
POST   /swipes/pass        { user_id }  → { passed }
POST   /swipes/super-like  { user_id }  → { super_liked, is_match, match, remaining_super_likes }
POST   /swipes/undo                     → { undone: false }   // unchanged stub
GET    /matches            ?limit&offset → { matches[], pagination }
DELETE /matches/:id                     → unmatch
POST   /reports            { user_id, reason, details? }
POST   /blocks             { user_id }
DELETE /blocks/:userId
GET    /blocks                          → { blocked_users[] }
```

## Discover changes

`discoveryService.discover` currently runs
`User.find({ _id: { $ne: me }, isDeleted: { $ne: true } })` — no exclusion, no
filtering. Phase A adds:

- exclude already-swiped (fixes the endless repeats)
- exclude blocked / blockedBy
- age and gender-preference filters, from fields the profile already collects
- distance, **only when `locationGeo` is populated** — degrade gracefully rather
  than returning an empty deck for users without location

Excluding swipes means the deck now **runs out**, which it never did before. The
empty state and `has_more` handling become real code paths.

## App-side work

Small, because the app is already built.

1. **Fix the Discover `RangeError`.** `CardSwiper` takes a stale index when the
   deck shrinks (`home_screen.dart:266`). This becomes a blocker: swipe exclusion
   makes an emptying deck the normal case, which is exactly the trip condition.
2. **Deck-empty state** — previously unreachable, now a real path.
3. **Unmatch entry point** — `DELETE /matches/:id` will exist with no caller.

Swipe wiring, the match dialog, the matches list, story gating, and report/block
all work unchanged once the backend responds.

## Testing

Backend, following existing `flame/__tests__` patterns (`node:test` +
`mongodb-memory-server`):

- swipe idempotency — double-liking neither duplicates nor double-matches
- mutual detection — A likes B (no match) → B likes A (match + conversation)
- simultaneous like race — concurrent inserts yield exactly one match
- **block is total** — one test per surface above; this is the failure mode that matters
- block unmatches — match ends, conversation leaves both lists
- super-like quota — decrements, resets daily, rejects at zero
- Discover exclusion — a swiped user never reappears; deck empties correctly
- report — persists, rejects self-reports, validates the reason enum

App: a widget test reproducing the `CardSwiper` `RangeError` on a shrinking deck,
plus the empty state.

## Phase B (separate spec)

BananaTalk's chat is far richer, but much of it is language-learning specific
(corrections, translation, TTS, vocabulary, quick replies) and does **not** apply
to a dating app. The relevant subset:

| Feature | Flame status |
|---|---|
| Media messages (image/video/voice/audio) | app calls the endpoints, no backend |
| Pin message | app calls it, no backend |
| Mute conversation | app calls it, no backend |
| Reply, forward, search, archive | neither side |
| Disappearing messages | neither — but a natural fit for dating |
| Reactions, edit/delete, read receipts, typing | already working in Flame |

The first three are the priority: the app already calls those endpoints, so they
are latent 404s the moment any UI surfaces them.
