# Chat Search, Archive and Translation — Design

**Date:** 2026-08-17
**Sub-project:** D of the chat/profile decomposition
**Repos:** `~/Projects/BananaTalk/backend` (the `flame/` sub-app) and `~/Desktop/Flame/flame_front_app`
**Reference implementation:** `~/Projects/BananaTalk/bananatalk_app` and the BananaTalk backend
**Predecessors:** `2026-08-16-matching-and-safety-design.md`, `2026-08-17-chat-enrichment-design.md`

## Problem

Three pieces of chat surface, related only by needing backend Flame does not
have. They are grouped because each is one route plus app wiring, not because
they form a feature.

One of the three is a **live defect**, not a missing feature. `message_bubble.dart:207`
renders a Translate control under every incoming text message. It calls
`POST /translate`, which resolves to `/flamebackend/v1/translate`. No such route
exists. Every tap 404s, and has since the control shipped.

## Scope

**In:** translation, archive, search — in that order.

**Out, and deliberately:**

- **Forward.** In a language-exchange app, forwarding shares a useful phrase.
  On a dating app it is the mechanic behind screenshot-and-share culture. The
  predecessor spec already recommended refusing to forward out of a
  since-blocked conversation; the simpler answer is not to build it.
- **Bookmarks.** Duplicates pin, which already has a backend, an app service
  call, and only needs UI (sub-project B).
- **Auto-translate.** BananaTalk has it (`chat/header/auto_translate_toggle.dart`).
  Flame's `translationProvider` is a per-message toggle, and auto-translating
  every incoming message multiplies a metered outbound call by the length of
  the conversation. Revisit once per-message translation has usage.
- **Disappearing messages.** Carried over from the predecessor spec's B5;
  independent of these three.

## What already exists — do not rebuild

Verified in the code, not assumed:

| Capability | Where | State |
|---|---|---|
| Translate control in the bubble | `message_bubble.dart:207`, `_TranslateSection` | shipped, calls a 404 |
| `TranslationService.translate()` | `lib/services/translation_service.dart` | shipped, posts `/translate` |
| Per-message translate toggle | `lib/providers/translation_provider.dart` | shipped |
| `Conversation.archivedBy` | `flame/models/Conversation.js` | field exists, no route |
| Archive exclusion in the list | `chatService.listConversations` | already filters `archivedBy.user` |
| Block / ended-match exclusions | `listConversations`, `_assertCanSendInto` | Phase A, must not regress |

---

## Translation

### Provider: LibreTranslate, not OpenAI

BananaTalk has two translation paths, and the obvious one is wrong for this.

| | `services/aiTranslationService.js` | `services/translationService.js` |
|---|---|---|
| Provider | OpenAI | LibreTranslate |
| Built for | grammar breakdown, idioms, alternatives | plain translation |
| Source language | **required** — 400 without it | auto-detects via `/detect` |
| Cost | per-call LLM | free / self-hostable |

Flame's shipped client sends `source_lang` as **optional**. It would 400 against
the OpenAI path on its own requests. A dating chat wants "what did they just
say", not a language lesson.

### Contract — fixed by the shipped app

```
POST /flamebackend/v1/translate
body:     { text, target_lang, source_lang? }
response: { success: true, data: { translated_text, detected_source_lang } }
```

`TranslationService._extractTranslation` accepts `translated_text`,
`translation` or `text`; emit `translated_text`. The request shape is not
negotiable without a coordinated app release.

### Design

- `flame/services/translationService.js` — `axios` to `LIBRETRANSLATE_URL`,
  mirroring the root service's shape. Under `flame/`, not a call into root
  code: the isolation rule has earned its keep twice, and root code can change
  under Flame without warning.
- **Caching is required, not an optimisation.** LibreTranslate is rate-limited,
  and the same message is re-translated every time a bubble rebuilds. A
  `Translation` collection in `flame_db`, keyed on a hash of
  (text, source_lang, target_lang), following `translationService.js:185`.
  The key uses the **detected** source language, not the requested one, so an
  auto-detect request and an explicit-source request for the same text share one
  entry instead of writing two. That means detection runs before the cache
  lookup on auto-detect requests; detection is the cheap half of the call.
- **Rate limited** at the route, following the `mediaUploadLimiter` already in
  `flame/routes/conversations.js`. Every call is outbound and metered.
- A provider outage returns a `ValidationError`-style 422 the UI can show, never
  a 500. BananaTalk's client special-cases the "API key / libretranslate" error
  text; Flame should return something equally recognisable.

### Environment

`LIBRETRANSLATE_URL` and `LIBRETRANSLATE_API_KEY` already exist in BananaTalk's
config. Flame reads the same two. If `LIBRETRANSLATE_URL` is unset the service
must say so at boot, the way `flame/utils/s3.js` now announces its bucket —
a wrong upload bucket was invisible for weeks because nothing said anything
until a user hit it.

---

## Archive

The cheapest of the three: the model field and the list filter both exist.

### Contract

```
POST   /flamebackend/v1/conversations/:id/archive
DELETE /flamebackend/v1/conversations/:id/archive
GET    /flamebackend/v1/conversations?archived=true
```

The first two follow the mute pair exactly (`routes/conversations.js:128-134`),
including `_assertParticipant` for the 403.

### The bug this must not ship

`listConversations` already excludes archived conversations, and there is no way
to list them. Archiving today would make a conversation **unreachable** — the
messages stay, the user cannot reach them. `?archived=true` is therefore part of
the minimum, not a follow-up.

Archived is per-user: `archivedBy` is an array of subdocuments, so archiving must
not change what the other participant sees. Guard duplicates with an explicit
`$ne` filter, never `$addToSet` — these subdocuments carry timestamps, so two
entries for one user are never equal and `$addToSet` will not dedupe. The
previous phase hit this trap twice.

### App

Swipe-to-archive on the conversation tile, and an entry point to the archived
list. Archive does not affect unread count or delivery.

---

## Search

Global across the caller's conversations.

### Contract

```
GET /flamebackend/v1/messages/search?q=<term>&limit=20&offset=0
response: { success: true, data: { messages: [...], total } }
```

Mirrors `routes/messages.js:41`, including its `searchLimiter` (20/min) and its
`Math.min(limit, 100)` cap.

### Mechanism

A MongoDB `$text` index on `Message.text`, as BananaTalk uses
(`controllers/messageSearch.js:44`), **with `default_language: 'none'`**.

That option is the one deliberate divergence from the reference. BananaTalk
stems for a single study language; Flame's users chat in whatever they share,
and stemming for the wrong language silently degrades matching. `'none'` gives
exact token matching across languages.

Media messages carry `text: ''` and so fall out naturally.

### The security rule — the reason this is a backend project

Search must not become a side door into the exclusions Phase A established. A
search that returns a message from a blocked pair reopens that hole through a
route nobody audited.

**Search resolves its allowed conversation ids by reusing
`listConversations`'s exclusion filter — the same code path, not a re-derived
equivalent.** Two copies of an exclusion rule drift, and only one of them gets
audited. It then text-searches within those ids, additionally excluding
`isDeleted: true` and any message whose `deletedFor` contains the caller.

**That filter is currently inline and must be extracted first.**
`chatService.listConversations` builds it at `chatService.js:152-171` —
`participants: { $all: [userId], $nin: hidden }` from `visibility.blockedIdsFor`
plus `matchService`'s ended matches, then `archivedBy.user: { $ne: userId }`.
None of it is reachable from another function today.

Extraction is part of this work, not a tidy-up, and it is the same move that
`_assertCanSendInto` required in the previous phase: the media send path was
written by copying the text path's guards, they disagreed within one commit, and
it cost a review round. Copying this filter into search would repeat that with
higher stakes, because the copy that drifts is the one enforcing blocks.

The extracted helper takes the archive state as a parameter, since
`?archived=true` needs the `archivedBy.user` condition inverted rather than
dropped:

```js
// Returns the conversation filter for `userId`, excluding blocked users and
// ended matches. `archived` selects which side of the archive line to return.
async function conversationFilterFor(userId, { archived = false } = {})
```

### App

A search screen following `chat/search/chat_search_screen.dart`: 500ms debounce,
results cleared when the query empties, explicit loading and error states, and a
result tap that opens the conversation.

---

## Testing

Backend tests follow the `flame/__tests__` conventions — `node:test` +
`mongodb-memory-server` — and the three standing corrections that have bitten
repeatedly: fixture names ≥2 characters, S3 env vars set before any `require`,
and every required service cleared from the require-cache array including
`matchService` and `Match`.

The tests that carry the design:

- **Search returns nothing from a blocked pair, and nothing from an ended
  match.** These two are the point of the security rule.
- Search excludes deleted messages, and messages deleted-for-the-caller.
- Search's `total` and returned length agree — one filter, as with
  `countDocuments` in `listConversations`.
- **Archive filters the default list without disturbing the block and
  ended-match exclusions.** Seed one archived, one blocked, one ended and one
  normal; assert only the normal one comes back.
- Archive affects only the archiving user.
- Archived conversations are reachable through `?archived=true`.
- Translation caches: a repeated request does not call the provider twice.
- A provider outage surfaces as a client-readable error, not a 500.

## Rollout

Translation first — it is the only one of the three fixing something users are
actively hitting. Then archive, which is the smallest. Then search, which is the
largest and the one with the security rule.

Before deploying: run `flame/scripts/drop-legacy-indexes.js` against the target
database and read the report. This project adds a `$text` index and a
`Translation` collection, and `flame_db` has held indexes from an earlier schema
that no test could see, because `mongodb-memory-server` starts empty.
