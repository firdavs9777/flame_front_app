# Chat Search, Archive and Translation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Flame's chat a translation endpoint the shipped app already calls, conversation archiving, and global message search that cannot see past a block.

**Architecture:** Three independent backend routes under `flame/`, each with app wiring. Translation proxies LibreTranslate with a cache in `flame_db`. Archive reuses the `archivedBy` field and list filter that already exist. Search reuses `listConversations`' exclusion filter — extracted first, never copied — to resolve which conversations the caller may search, then runs a `$text` query inside them.

**Tech Stack:** Node/Express, Mongoose on Flame's own `getConn()` connection, `axios`, `express-rate-limit`, `zod`. App: Flutter/Riverpod. Tests: `node:test` + `mongodb-memory-server`; `flutter test`.

**Spec:** `docs/superpowers/specs/2026-08-17-chat-search-archive-translation-design.md`

## Global Constraints

- **Two repos.** Backend: `~/Projects/BananaTalk/backend` (paths relative to it unless marked **APP**). App: `~/Desktop/Flame/flame_front_app` (marked **APP**).
- **Backend: only touch files under `flame/`.** BananaTalk's root code serves live users. A change outside `flame/` is a defect, not a shortcut — including `server.js` and root `services/`.
- Flame models end with `module.exports = getConn().model('Name', schema);` — never `mongoose.model()`.
- User ids are `String`. `auth` sets `req.user = { id: payload.userId }`.
- Response envelope is `{ success: true, data: {...} }`. Errors come from `flame/utils/errors.js`: `ValidationError` → 422, `NotFoundError` → 404, `ForbiddenError` → 403. Anything that is not a `FlameError` reaches the generic handler as a **500**, so wrap third-party failures.
- **The exclusion rule is the point of this project.** Blocked users and ended-match partners must not be reachable through any new route. Reuse the extracted filter; never re-derive it.
- Backend tests: `node --test flame/__tests__/<file>` — **run in the FOREGROUND, one file at a time.** Never background a test run; never run the whole suite while iterating (it takes ~4 minutes and has hung agents).
- **Standing test corrections** (these have bitten repeatedly):
  1. Fixture user names must be ≥2 characters (`User.name` has `minlength: 2`). A one-letter name throws before teardown registers, leaking the mongod process and hanging the suite.
  2. Set `FLAME_SPACES_BUCKET`, `SPACES_ENDPOINT`, `DO_SPACES_KEY`, `DO_SPACES_SECRET` **before** any `require` — `flame/utils/s3.js` reads them at module load.
  3. Clear every service you require from the require-cache array, **including `matchService` and `Match`** for anything touching chat.
- App baselines to preserve: `flutter test` all passing, `flutter analyze` **0 errors and 0 warnings**.
- **Known flake:** a full-suite backend run fails roughly one test per run, a different one each time, and does so on `main` too. Individual files pass. Do not chase it; re-run the single file to confirm.

---

## File Structure

**Backend (all under `flame/`)**

| File | Responsibility |
|---|---|
| `models/Translation.js` (new) | Cache collection: one translated string, keyed by content hash + language pair |
| `services/translationService.js` (new) | LibreTranslate calls (detect + translate) and cache read/write |
| `controllers/translationController.js` (new) | Request → service → envelope |
| `routes/translate.js` (new) | `POST /translate`, rate limited |
| `index.js` (modify) | Mount `/translate` |
| `services/chatService.js` (modify) | Extract `conversationFilterFor`; add `archive`/`unarchive`; `listConversations` takes `archived` |
| `services/messageSearchService.js` (new) | Global search over allowed conversations |
| `models/Message.js` (modify) | `$text` index on `text` with `default_language: 'none'` |
| `controllers/chatController.js` (modify) | Archive handlers, search handler, `archived` query on list |
| `routes/conversations.js` (modify) | Archive routes |
| `routes/messages.js` (modify) | `GET /messages/search` |

**App (all under `lib/`)**

| File | Responsibility |
|---|---|
| `services/chat_service.dart` (modify) | `archiveConversation`, `unarchiveConversation`, `searchMessages`, `getConversations(archived:)` |
| `providers/chat_provider.dart` (modify) | Archive actions on the conversations notifier |
| `screens/chat/chat_search_screen.dart` (new) | Debounced search UI |
| `screens/chat/archived_conversations_screen.dart` (new) | The archived list |
| `screens/chat/matches_screen.dart` (modify) | Swipe-to-archive, entry points to search and archive |

---

### Task 1: Translation cache model and service

**Files:**
- Create: `flame/models/Translation.js`
- Create: `flame/services/translationService.js`
- Test: `flame/__tests__/translationService.test.js`

**Interfaces:**
- Produces: `translationService.translate({ text, targetLang, sourceLang })` → `{ translatedText, detectedSourceLang, cached }`; `translationService.LIBRETRANSLATE_URL`

**The cache key uses the DETECTED source language**, not the requested one, so an auto-detect request and an explicit-source request for the same text share one entry. Detection therefore runs before the cache lookup when `sourceLang` is absent; detection is the cheap half of the call.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/translationService.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

process.env.FLAME_SPACES_BUCKET = 't';
process.env.SPACES_ENDPOINT = 'e';
process.env.DO_SPACES_KEY = 'k';
process.env.DO_SPACES_SECRET = 's';
process.env.LIBRETRANSLATE_URL = 'https://libre.test';

const AXIOS = require.resolve('axios');

// Stub axios so no network call happens and every request is observable.
function withStubbedAxios(handler) {
  const real = require.cache[AXIOS];
  require.cache[AXIOS] = {
    id: AXIOS, filename: AXIOS, loaded: true,
    exports: { post: handler },
  };
  return () => {
    if (real) require.cache[AXIOS] = real; else delete require.cache[AXIOS];
  };
}

async function setup() {
  await dbHelper.start();
  ['../db', '../models/Translation', '../services/translationService']
    .forEach((p) => { try { delete require.cache[require.resolve(p)]; } catch {} });
  const { connect } = require('../db');
  await connect();
  return require('../services/translationService');
}

const teardown = (t) => t.after(async () => {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
});

test('translates with an explicit source language', async (t) => {
  const calls = [];
  const restore = withStubbedAxios(async (url, body) => {
    calls.push({ url, body });
    return { data: { translatedText: 'hola' } };
  });
  t.after(restore);

  const svc = await setup();
  teardown(t);

  const out = await svc.translate({ text: 'hello', targetLang: 'es', sourceLang: 'en' });

  assert.equal(out.translatedText, 'hola');
  assert.equal(out.detectedSourceLang, 'en');
  assert.equal(out.cached, false);
  assert.equal(calls.length, 1, 'an explicit source must skip detection');
  assert.match(calls[0].url, /\/translate$/);
  assert.equal(calls[0].body.q, 'hello');
  assert.equal(calls[0].body.source, 'en');
  assert.equal(calls[0].body.target, 'es');
});

test('detects the source language when none is given', async (t) => {
  const calls = [];
  const restore = withStubbedAxios(async (url, body) => {
    calls.push({ url, body });
    if (url.endsWith('/detect')) return { data: [{ language: 'fr', confidence: 99 }] };
    return { data: { translatedText: 'hello' } };
  });
  t.after(restore);

  const svc = await setup();
  teardown(t);

  const out = await svc.translate({ text: 'bonjour', targetLang: 'en' });

  assert.equal(out.translatedText, 'hello');
  assert.equal(out.detectedSourceLang, 'fr');
  assert.equal(calls.length, 2);
  assert.match(calls[0].url, /\/detect$/, 'detection runs first');
});

test('a repeat request is served from the cache without calling the provider', async (t) => {
  let providerCalls = 0;
  const restore = withStubbedAxios(async (url) => {
    providerCalls += 1;
    if (url.endsWith('/detect')) return { data: [{ language: 'en' }] };
    return { data: { translatedText: 'hola' } };
  });
  t.after(restore);

  const svc = await setup();
  teardown(t);

  const first = await svc.translate({ text: 'hello', targetLang: 'es', sourceLang: 'en' });
  const second = await svc.translate({ text: 'hello', targetLang: 'es', sourceLang: 'en' });

  assert.equal(first.cached, false);
  assert.equal(second.cached, true);
  assert.equal(second.translatedText, 'hola');
  assert.equal(providerCalls, 1,
    'LibreTranslate is rate limited and a bubble re-translates on every rebuild');
});

test('an auto-detect request hits the cache written by an explicit-source one', async (t) => {
  let translateCalls = 0;
  const restore = withStubbedAxios(async (url) => {
    if (url.endsWith('/detect')) return { data: [{ language: 'en' }] };
    translateCalls += 1;
    return { data: { translatedText: 'hola' } };
  });
  t.after(restore);

  const svc = await setup();
  teardown(t);

  await svc.translate({ text: 'hello', targetLang: 'es', sourceLang: 'en' });
  const auto = await svc.translate({ text: 'hello', targetLang: 'es' });

  assert.equal(auto.cached, true,
    'the key is the DETECTED language, so both requests resolve to one entry');
  assert.equal(translateCalls, 1);
});

test('a provider failure is a ValidationError, not a raw throw', async (t) => {
  const restore = withStubbedAxios(async () => { throw new Error('ECONNREFUSED'); });
  t.after(restore);

  const svc = await setup();
  teardown(t);

  await assert.rejects(
    () => svc.translate({ text: 'hello', targetLang: 'es', sourceLang: 'en' }),
    (e) => e.status === 422,
    'an outage must reach the client as something it can show, never a 500',
  );
});

test('empty text is rejected before any provider call', async (t) => {
  let called = false;
  const restore = withStubbedAxios(async () => { called = true; return { data: {} }; });
  t.after(restore);

  const svc = await setup();
  teardown(t);

  await assert.rejects(
    () => svc.translate({ text: '   ', targetLang: 'es' }),
    (e) => e.status === 422,
  );
  assert.equal(called, false);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Projects/BananaTalk/backend && node --test flame/__tests__/translationService.test.js`
Expected: FAIL — `Cannot find module '../services/translationService'`

- [ ] **Step 3: Write the cache model**

Create `flame/models/Translation.js`:

```js
const mongoose = require('mongoose');
const { getConn } = require('../db');

// One translated string. Keyed by a hash of the source text plus the language
// pair rather than the text itself, because message text runs to 2000
// characters and an index on that is neither small nor fast.
const translationSchema = new mongoose.Schema(
  {
    key: { type: String, required: true, unique: true, index: true },
    sourceLang: { type: String, required: true },
    targetLang: { type: String, required: true },
    translatedText: { type: String, required: true },
  },
  { timestamps: true },
);

module.exports = getConn().model('Translation', translationSchema);
```

- [ ] **Step 4: Write the service**

Create `flame/services/translationService.js`:

```js
const crypto = require('crypto');
const axios = require('axios');
const Translation = require('../models/Translation');
const logger = require('../utils/logger');
const { ValidationError } = require('../utils/errors');

const LIBRETRANSLATE_URL =
  process.env.LIBRETRANSLATE_URL || 'https://libretranslate.com';
const LIBRETRANSLATE_API_KEY = process.env.LIBRETRANSLATE_API_KEY || null;

if (!process.env.LIBRETRANSLATE_URL) {
  // Say it at boot rather than when a user taps Translate. A misconfigured
  // upload bucket stayed invisible for weeks because nothing announced itself
  // until someone hit it.
  logger.warn(
    `LIBRETRANSLATE_URL not set — falling back to ${LIBRETRANSLATE_URL}, `
    + 'which is rate limited and may reject production traffic.',
  );
}

function cacheKey(text, sourceLang, targetLang) {
  return crypto
    .createHash('sha256')
    .update(`${sourceLang}:${targetLang}:${text}`)
    .digest('hex');
}

// LibreTranslate takes the API key in the body, and only when it is set —
// sending an empty one is rejected by some instances.
function body(fields) {
  const out = { ...fields };
  if (LIBRETRANSLATE_API_KEY && LIBRETRANSLATE_API_KEY.trim() !== '') {
    out.api_key = LIBRETRANSLATE_API_KEY;
  }
  return out;
}

async function detect(text) {
  const res = await axios.post(
    `${LIBRETRANSLATE_URL}/detect`,
    body({ q: text }),
    { timeout: 5000, headers: { 'Content-Type': 'application/json' } },
  );
  if (Array.isArray(res.data) && res.data.length > 0 && res.data[0].language) {
    return res.data[0].language;
  }
  throw new Error('LibreTranslate returned no detection');
}

/**
 * Translates `text` into `targetLang`.
 *
 * `sourceLang` is optional; when absent the language is detected first, and the
 * DETECTED value is what the cache is keyed on. That way an auto-detect request
 * and an explicit-source request for the same text share one entry instead of
 * writing two.
 */
async function translate({ text, targetLang, sourceLang }) {
  const trimmed = (text || '').trim();
  if (!trimmed) throw new ValidationError('text is required');
  if (!targetLang) throw new ValidationError('target_lang is required');

  try {
    const source = sourceLang || (await detect(trimmed));

    // Nothing to do, and no reason to spend a call on it.
    if (source === targetLang) {
      return { translatedText: trimmed, detectedSourceLang: source, cached: true };
    }

    const key = cacheKey(trimmed, source, targetLang);
    const hit = await Translation.findOne({ key });
    if (hit) {
      return {
        translatedText: hit.translatedText,
        detectedSourceLang: source,
        cached: true,
      };
    }

    const res = await axios.post(
      `${LIBRETRANSLATE_URL}/translate`,
      body({ q: trimmed, source, target: targetLang, format: 'text' }),
      { timeout: 10000, headers: { 'Content-Type': 'application/json' } },
    );

    const translatedText = res.data && res.data.translatedText;
    if (!translatedText) throw new Error('LibreTranslate returned no translation');

    // Best effort: a cache write failure must not fail the translation the
    // user is waiting for.
    try {
      await Translation.create({
        key, sourceLang: source, targetLang, translatedText,
      });
    } catch (e) {
      logger.warn(`translation cache write failed: ${e.message}`);
    }

    return { translatedText, detectedSourceLang: source, cached: false };
  } catch (err) {
    if (err instanceof ValidationError) throw err;
    // Everything below here is the provider being unreachable, slow or
    // unhappy. A ValidationError reaches the client as a 422 it can show;
    // rethrowing would hit the generic handler and become a 500.
    logger.error(`translation failed: ${err.message}`);
    throw new ValidationError('Translation is unavailable right now');
  }
}

module.exports = { translate, LIBRETRANSLATE_URL };
```

- [ ] **Step 5: Run test to verify it passes**

Run: `node --test flame/__tests__/translationService.test.js`
Expected: PASS — 6 tests

- [ ] **Step 6: Commit**

```bash
git add flame/models/Translation.js flame/services/translationService.js \
        flame/__tests__/translationService.test.js
git commit -m "feat(flame): add a cached LibreTranslate translation service"
```

---

### Task 2: Translation route

**Files:**
- Create: `flame/controllers/translationController.js`
- Create: `flame/routes/translate.js`
- Modify: `flame/index.js`
- Test: `flame/__tests__/translate.test.js`

**Interfaces:**
- Consumes: `translationService.translate({ text, targetLang, sourceLang })` (Task 1)
- Produces: `POST /flamebackend/v1/translate` → `{ success: true, data: { translated_text, detected_source_lang, cached } }`

**The request shape is fixed by the shipped app.** `lib/services/translation_service.dart` posts `{ text, target_lang, source_lang? }` and reads `data['translated_text']`. Do not rename either.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/translate.test.js`. Model the setup on `flame/__tests__/conversations.test.js` (it builds an app via `./helpers/app` and registers users through `/flamebackend/v1/auth/register`), applying all three standing corrections, and stub `axios` via the require-cache technique from Task 1. Cover, as real assertions:

```js
// 1. POST /translate with { text, target_lang: 'es', source_lang: 'en' } returns
//    201 or 200 with data.translated_text set, and data.detected_source_lang 'en'.
// 2. The same request twice returns data.cached true the second time.
// 3. Omitting source_lang still succeeds and reports the detected language.
// 4. Missing text is 422. Missing target_lang is 422.
// 5. An unauthenticated request is 401 — translation is a metered outbound
//    call and must not be open.
// 6. A provider outage returns 422 with a readable message, never 500.
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/translate.test.js`
Expected: FAIL — 404, route not mounted

- [ ] **Step 3: Write the controller**

Create `flame/controllers/translationController.js`:

```js
const translationService = require('../services/translationService');

async function translate(req, res) {
  const out = await translationService.translate({
    text: req.body.text,
    targetLang: req.body.target_lang,
    sourceLang: req.body.source_lang,
  });

  res.json({
    success: true,
    data: {
      // These key names are what lib/services/translation_service.dart parses.
      translated_text: out.translatedText,
      detected_source_lang: out.detectedSourceLang,
      cached: out.cached,
    },
  });
}

module.exports = { translate };
```

- [ ] **Step 4: Write the route**

Create `flame/routes/translate.js`:

```js
const express = require('express');
const rateLimit = require('express-rate-limit');
const { z } = require('zod');
const asyncHandler = require('../middleware/asyncHandler');
const auth = require('../middleware/auth');
const validate = require('../middleware/validate');
const ctrl = require('../controllers/translationController');

const router = express.Router();

// Every call is an outbound, metered request to a rate-limited provider.
// Keyed on the user rather than the IP: several users behind one carrier NAT
// must not throttle each other.
const translateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 30,
  keyGenerator: (req) => (req.user ? req.user.id : req.ip),
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: { code: 'RATE_LIMITED', message: 'Too many translations. Please slow down.' },
  },
});

const translateSchema = z.object({
  text: z.string().min(1).max(2000),
  target_lang: z.string().min(2).max(8),
  source_lang: z.string().min(2).max(8).optional(),
});

router.post('/', auth, translateLimiter, validate.body(translateSchema),
  asyncHandler(ctrl.translate));

module.exports = router;
```

- [ ] **Step 5: Mount it**

In `flame/index.js`, beside the other `router.use` lines:

```js
router.use('/translate', require('./routes/translate'));
```

- [ ] **Step 6: Run test to verify it passes**

Run: `node --test flame/__tests__/translate.test.js`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add flame/controllers/translationController.js flame/routes/translate.js \
        flame/index.js flame/__tests__/translate.test.js
git commit -m "feat(flame): add the /translate route the shipped app already calls"
```

---

### Task 3: Extract the conversation exclusion filter

**Files:**
- Modify: `flame/services/chatService.js`
- Test: `flame/__tests__/conversationFilter.test.js`

**Interfaces:**
- Produces: `chatService.conversationFilterFor(userId, { archived })` → a Mongoose filter object. `archived` is `false` (default list), `true` (archived list), or `'any'` (both — used by search).

**This task changes no behaviour.** It is a pure extraction, and it exists because the next two tasks must not copy this logic. When the media send path copied the text path's guards last phase, the two disagreed inside a single commit and it cost a review round. Here the copy that drifts would be the one enforcing blocks.

The current code lives at `flame/services/chatService.js:152-171` inside `listConversations`. Read it before editing; the comments explain why `$all` accompanies `$nin` and must move with the code.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/conversationFilter.test.js` covering, as real assertions against a seeded database:

```js
// 1. With no blocks and no ended matches, the filter is
//    { participants: userId, 'archivedBy.user': { $ne: userId } }.
// 2. A blocked partner puts their id in participants.$nin, and userId stays in
//    $all — dropping $all would return conversations the caller is not in.
// 3. An ended-match partner appears in the same $nin.
// 4. A user both blocked and unmatched appears ONCE (the ids are de-duplicated).
// 5. { archived: true } inverts the archive condition to
//    { 'archivedBy.user': userId } rather than dropping it — otherwise the
//    archived list would show everything.
// 6. { archived: 'any' } omits the archivedBy condition entirely, while still
//    applying the block and ended-match exclusions. Search relies on this.
// 7. Feeding the filter to Conversation.find returns exactly the conversations
//    listConversations returns for the same user. This is the assertion that
//    proves the extraction changed nothing.
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/conversationFilter.test.js`
Expected: FAIL — `conversationFilterFor is not a function`

- [ ] **Step 3: Extract the filter**

In `flame/services/chatService.js`, add above `listConversations`:

```js
/**
 * The conversation filter for `userId`.
 *
 * Extracted from listConversations so search and the archived list share ONE
 * implementation of the exclusion rule. Two copies drift, and only one of them
 * gets audited — which matters more here than anywhere else in the codebase,
 * because this is what keeps blocked and unmatched people out of every list.
 *
 * `archived` selects which side of the archive line to return: false for the
 * default list, true for the archived one, and 'any' to drop the condition
 * entirely. It INVERTS rather than drops for the true case, so the archived
 * list is not "everything".
 *
 * 'any' exists for search, which spans both — a conversation the caller
 * archived is still theirs to search. Without it search would call this twice
 * and run the block and ended-match lookups twice for one query.
 */
async function conversationFilterFor(userId, { archived = false } = {}) {
  const filter = { participants: userId };

  // A blocked person must leave the list entirely, not just be un-messageable.
  // So must an unmatched one: the conversation outlives the match, so without
  // the ended-match ids here an unmatch would leave the chat sitting in both
  // users' Messages lists forever.
  //
  // `$all` keeps "userId is a participant"; `$nin` drops any conversation whose
  // participants include someone on either side of a block or an ended match.
  // Written as one assignment because it REPLACES the plain
  // `participants: userId` above. Both id sets come from ONE query each, not
  // one per conversation.
  const [blocked, unmatched] = await Promise.all([
    visibility.blockedIdsFor(userId),
    _matchService().endedPartnerIdsFor(userId),
  ]);
  const hidden = [...new Set([...blocked, ...unmatched])];
  if (hidden.length) filter.participants = { $all: [userId], $nin: hidden };

  // Archive is per-user, so it filters on this conversation's own array rather
  // than on the participant ids the block/ended-match exclusions use above.
  if (archived !== 'any') {
    filter['archivedBy.user'] = archived ? userId : { $ne: userId };
  }

  return filter;
}
```

Then replace the body of `listConversations` down to the `filter` construction:

```js
async function listConversations(userId, { limit, offset, archived = false }) {
  const filter = await conversationFilterFor(userId, { archived });
  const total = await Conversation.countDocuments(filter);
  // ... the rest of the function is unchanged ...
```

Export `conversationFilterFor` from the module.

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test flame/__tests__/conversationFilter.test.js`
Expected: PASS

- [ ] **Step 5: Prove the extraction changed nothing**

Run, in the foreground, one at a time:

```
node --test flame/__tests__/conversations.test.js
node --test flame/__tests__/blockEnforcement.test.js
node --test flame/__tests__/unmatchEnforcement.test.js
node --test flame/__tests__/conversationControlsEffects.test.js
```

Expected: all pass. These are the tests that would catch a broken exclusion. If any fails, the extraction is wrong — fix the extraction, never the test.

- [ ] **Step 6: Commit**

```bash
git add flame/services/chatService.js flame/__tests__/conversationFilter.test.js
git commit -m "refactor(flame): extract the conversation exclusion filter so search can reuse it"
```

---

### Task 4: Archive routes

**Files:**
- Modify: `flame/services/chatService.js`, `flame/controllers/chatController.js`, `flame/routes/conversations.js`
- Test: `flame/__tests__/archive.test.js`

**Interfaces:**
- Consumes: `conversationFilterFor` (Task 3), `_findConversation`, `_assertParticipant`
- Produces: `POST`/`DELETE /conversations/:id/archive`; `GET /conversations?archived=true`

**Do not use `$addToSet`.** `archivedBy` holds subdocuments carrying an `archivedAt` timestamp, so two entries for one user are never equal and `$addToSet` will not dedupe. Guard with an explicit `$ne` filter — the previous phase hit this trap twice.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/archive.test.js` covering, as real assertions:

```js
// 1. POST /conversations/:id/archive removes it from GET /conversations.
// 2. GET /conversations?archived=true returns it — without this the
//    conversation is unreachable and archiving is data loss by another name.
// 3. Archiving affects only the archiving user: the other participant's
//    default list still contains it.
// 4. DELETE /conversations/:id/archive puts it back in the default list.
// 5. Archiving twice leaves exactly ONE entry in archivedBy (the $addToSet trap).
// 6. A non-participant gets 403 on both verbs.
// 7. Archiving does not change unreadCount, and a message sent afterwards
//    still increments it.
// 8. The archived list still excludes blocked and ended-match partners: seed
//    one archived+blocked and one archived+normal, and assert only the normal
//    one comes back. This is the regression that reusing the filter prevents.
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/archive.test.js`
Expected: FAIL — 404, routes not mounted

- [ ] **Step 3: Add the model field if it is absent**

`flame/models/Conversation.js` should already have:

```js
    archivedBy: {
      type: [{
        user: { type: String, required: true },
        archivedAt: { type: Date, default: Date.now },
      }],
      default: [],
    },
```

Read the file and confirm. If it is missing, add it beside `mutedBy` and `pinnedBy`.

- [ ] **Step 4: Add the service methods**

In `flame/services/chatService.js`:

```js
async function archiveConversation(userId, conversationId) {
  const conv = await _findConversation(conversationId);
  _assertParticipant(conv, userId);

  // An explicit $ne guard, not $addToSet: these subdocuments carry an
  // archivedAt, so no two entries for one user are ever equal and $addToSet
  // would happily add a second.
  await Conversation.updateOne(
    { _id: conv._id, 'archivedBy.user': { $ne: userId } },
    { $push: { archivedBy: { user: userId, archivedAt: new Date() } } },
  );
  return { archived: true };
}

async function unarchiveConversation(userId, conversationId) {
  const conv = await _findConversation(conversationId);
  _assertParticipant(conv, userId);
  await Conversation.updateOne(
    { _id: conv._id },
    { $pull: { archivedBy: { user: userId } } },
  );
  return { archived: false };
}
```

Export both.

- [ ] **Step 5: Add the controller handlers and the list query**

In `flame/controllers/chatController.js`:

```js
async function archiveConversation(req, res) {
  const data = await chatService.archiveConversation(req.user.id, req.params.id);
  res.json({ success: true, data });
}

async function unarchiveConversation(req, res) {
  const data = await chatService.unarchiveConversation(req.user.id, req.params.id);
  res.json({ success: true, data });
}
```

and in the existing `listConversations` handler, pass the query through:

```js
  const archived = req.query.archived === 'true';
```

then include `archived` in the options object handed to `chatService.listConversations`.

- [ ] **Step 6: Mount the routes**

In `flame/routes/conversations.js`, beside the mute pair:

```js
router.post('/:id/archive', auth, validate.params(idParam),
  asyncHandler(ctrl.archiveConversation));
router.delete('/:id/archive', auth, validate.params(idParam),
  asyncHandler(ctrl.unarchiveConversation));
```

Add `archived` to whatever zod schema validates the list query, as
`z.enum(['true', 'false']).optional()`. If the list route has no query schema,
do not add one — read `req.query.archived` in the controller as above.

- [ ] **Step 7: Run test to verify it passes**

Run: `node --test flame/__tests__/archive.test.js`
Expected: PASS

- [ ] **Step 8: Confirm nothing regressed**

Run: `node --test flame/__tests__/conversations.test.js`
Then: `node --test flame/__tests__/conversationControlsEffects.test.js`
Expected: both pass.

- [ ] **Step 9: Commit**

```bash
git add flame/services/chatService.js flame/controllers/chatController.js \
        flame/routes/conversations.js flame/models/Conversation.js \
        flame/__tests__/archive.test.js
git commit -m "feat(flame): archive and unarchive a conversation"
```

---

### Task 5: Message search

**Files:**
- Modify: `flame/models/Message.js`
- Create: `flame/services/messageSearchService.js`
- Modify: `flame/controllers/chatController.js`, `flame/routes/messages.js`
- Test: `flame/__tests__/messageSearch.test.js`

**Interfaces:**
- Consumes: `chatService.conversationFilterFor(userId, { archived })` (Task 3)
- Produces: `GET /messages/search?q=&limit=&offset=` → `{ success: true, data: { messages: [...], total } }`

**The security rule is the point of this task.** Search must not return a message from a conversation the caller could not open. It resolves allowed conversation ids through `conversationFilterFor` — the same code path the list uses — and never re-derives the exclusion.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/messageSearch.test.js` covering, as real assertions:

```js
// 1. Searching a word returns the matching message, with its conversation id.
// 2. A message in a BLOCKED pair's conversation is never returned, even though
//    its text matches. This is the hole the design exists to keep shut.
// 3. A message in an ENDED-match conversation is never returned.
// 4. A message belonging to someone else's conversation entirely is never
//    returned.
// 5. isDeleted messages are excluded.
// 6. A message whose deletedFor contains the caller is excluded, while the
//    other participant can still find it.
// 7. total and the returned length agree under paging: seed 3 matches, request
//    limit 2, assert messages.length === 2 and total === 3.
// 8. limit is capped at 100 even when a larger one is asked for.
// 9. An empty q is 422 rather than returning the whole mailbox.
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test flame/__tests__/messageSearch.test.js`
Expected: FAIL — 404, route not mounted

- [ ] **Step 3: Add the text index**

In `flame/models/Message.js`, before the `module.exports` line:

```js
// `default_language: 'none'` disables stemming. BananaTalk stems for one study
// language; Flame's users chat in whatever they share, and stemming for the
// wrong language silently degrades matching. 'none' gives exact token matching
// across every language.
messageSchema.index({ text: 'text' }, { default_language: 'none' });
```

- [ ] **Step 4: Write the service**

Create `flame/services/messageSearchService.js`:

```js
const Conversation = require('../models/Conversation');
const Message = require('../models/Message');
const { ValidationError } = require('../utils/errors');

const MAX_LIMIT = 100;

// Required lazily: chatService pulls in matchService and userService, and a
// top-level require here would make the import graph circular.
const _chatService = () => require('./chatService');

/**
 * Searches the caller's messages.
 *
 * Scope comes from chatService.conversationFilterFor — the SAME filter the
 * Messages list uses — so a blocked or unmatched partner's messages are
 * unreachable here for exactly the reason they are unreachable there. Deriving
 * the exclusion again would create a second copy to audit, and search is the
 * copy nobody would think to check.
 */
async function search(userId, { q, limit = 20, offset = 0 }) {
  const term = (q || '').trim();
  if (!term) throw new ValidationError('q is required');

  const take = Math.min(Number(limit) || 20, MAX_LIMIT);
  const skip = Math.max(Number(offset) || 0, 0);

  // 'any' spans both sides of the archive line — a conversation the caller
  // archived is still theirs to search — in ONE call. Calling this twice would
  // run the block and ended-match lookups twice for a single query.
  const filter = await _chatService().conversationFilterFor(userId, { archived: 'any' });
  const convs = await Conversation.find(filter).select('_id');
  const ids = convs.map((c) => c._id.toString());
  if (ids.length === 0) return { messages: [], total: 0 };

  const messageFilter = {
    conversationId: { $in: ids },
    isDeleted: false,
    deletedFor: { $ne: userId },
    $text: { $search: term },
  };

  const total = await Message.countDocuments(messageFilter);
  const messages = await Message.find(messageFilter)
    .sort({ createdAt: -1 })
    .skip(skip)
    .limit(take);

  return { messages, total };
}

module.exports = { search, MAX_LIMIT };
```

- [ ] **Step 5: Add the controller handler**

In `flame/controllers/chatController.js`:

```js
async function searchMessages(req, res) {
  const { messages, total } = await require('../services/messageSearchService')
    .search(req.user.id, {
      q: req.query.q,
      limit: req.query.limit,
      offset: req.query.offset,
    });

  res.json({
    success: true,
    data: {
      messages: messages.map((m) => ({
        ...chatService.toMessage(m),
        conversation_id: m.conversationId,
      })),
      total,
    },
  });
}
```

`toMessage` must be exported from `chatService` for this. If it is not, export it.

- [ ] **Step 6: Mount the route**

In `flame/routes/messages.js`, **above** the `/:id` routes:

```js
const searchQuery = z.object({
  q: z.string().min(1).max(200),
  limit: z.string().regex(/^\d+$/).optional(),
  offset: z.string().regex(/^\d+$/).optional(),
});

// Mounted before the /:id routes so 'search' is never read as an id.
router.get('/search', auth, searchLimiter, validate.query(searchQuery),
  asyncHandler(ctrl.searchMessages));
```

with a limiter beside it, following the one in `routes/conversations.js`:

```js
const searchLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  keyGenerator: (req) => (req.user ? req.user.id : req.ip),
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: { code: 'RATE_LIMITED', message: 'Too many searches. Please slow down.' },
  },
});
```

Require `rateLimit` and `z` at the top if not already present.

- [ ] **Step 7: Run test to verify it passes**

Run: `node --test flame/__tests__/messageSearch.test.js`
Expected: PASS

- [ ] **Step 8: Confirm the exclusions still hold everywhere else**

Run: `node --test flame/__tests__/blockEnforcement.test.js`
Then: `node --test flame/__tests__/unmatchEnforcement.test.js`
Expected: both pass.

- [ ] **Step 9: Commit**

```bash
git add flame/models/Message.js flame/services/messageSearchService.js \
        flame/controllers/chatController.js flame/routes/messages.js \
        flame/__tests__/messageSearch.test.js
git commit -m "feat(flame): global message search that cannot see past a block"
```

---

### Task 6: App — archive and search service calls

**Files:**
- Modify: `APP lib/services/chat_service.dart`
- Modify: `APP lib/providers/chat_provider.dart`
- Test: `APP test/services/chat_archive_search_test.dart`

**Interfaces:**
- Consumes: the routes from Tasks 4 and 5
- Produces:
  - `ChatService.archiveConversation(String id)` → `ServiceResult<void>`
  - `ChatService.unarchiveConversation(String id)` → `ServiceResult<void>`
  - `ChatService.searchMessages({required String query, int limit, int offset})` → `ServiceResult<List<Message>>`
  - `ConversationsNotifier.archive(String id)` / `.unarchive(String id)` → `Future<String?>` (null on success, else an error message)

- [ ] **Step 1: Write the failing test**

Create `APP test/services/chat_archive_search_test.dart`. Follow the pattern in `test/services/chat_service_test.dart` (it drives `ChatService` against a stubbed `ApiClient`). Assert:

```dart
// 1. archiveConversation posts to '/conversations/<id>/archive'.
// 2. unarchiveConversation issues a DELETE to the same path — NOT a POST with a
//    flag. The mute pair got this wrong in a shipped client and every "unmute"
//    silenced the conversation permanently.
// 3. searchMessages issues a GET to '/messages/search' passing q, limit and
//    offset through ApiClient's queryParams — NOT concatenated into the path,
//    which would double-encode a query containing a space or an &.
// 4. searchMessages parses data['messages'] into Message objects and returns
//    them; a missing 'messages' key yields an empty list rather than throwing.
// 5. A failed response surfaces as ServiceResult.failure with the server's
//    message, not a generic string.
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Desktop/Flame/flame_front_app && flutter test test/services/chat_archive_search_test.dart`
Expected: FAIL — the methods are not defined

- [ ] **Step 3: Add the service methods**

In `APP lib/services/chat_service.dart`:

```dart
  /// Archives a conversation for the current user only.
  Future<ServiceResult<void>> archiveConversation(String conversationId) async {
    final response = await _apiClient.post('/conversations/$conversationId/archive');
    if (response.success) return ServiceResult.success(null);
    return ServiceResult.failure(response.error ?? 'Failed to archive');
  }

  /// Unarchives. A DELETE, not a POST with a flag — the mute pair shipped with
  /// that mistake and every "unmute" muted the conversation forever.
  Future<ServiceResult<void>> unarchiveConversation(String conversationId) async {
    final response = await _apiClient.delete('/conversations/$conversationId/archive');
    if (response.success) return ServiceResult.success(null);
    return ServiceResult.failure(response.error ?? 'Failed to unarchive');
  }

  /// Searches every conversation the user can still open.
  Future<ServiceResult<List<Message>>> searchMessages({
    required String query,
    int limit = 20,
    int offset = 0,
  }) async {
    // queryParams, not string concatenation: ApiClient.get already encodes,
    // and a hand-built string double-encodes anything with a space or an &.
    final response = await _apiClient.get(
      '/messages/search',
      queryParams: {
        'q': query,
        'limit': '$limit',
        'offset': '$offset',
      },
    );

    if (response.success && response.data != null) {
      final raw = response.data['messages'] as List? ?? [];
      return ServiceResult.success(
        raw.map((m) => Message.fromJson(m as Map<String, dynamic>)).toList(),
      );
    }
    return ServiceResult.failure(response.error ?? 'Search failed');
  }
```

- [ ] **Step 4: Add the provider actions**

In `APP lib/providers/chat_provider.dart`, on `ConversationsNotifier`:

```dart
  /// Archives and drops the conversation from the cached list, so the row
  /// disappears without waiting for a refetch.
  Future<String?> archive(String conversationId) async {
    final result = await _chatService.archiveConversation(conversationId);
    if (!result.success) return ErrorStringsFor.fromString(result.error);

    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncValue.data(
        current.where((c) => c.id != conversationId).toList(),
      );
    }
    return null;
  }

  /// Unarchives. The row is not added back to this list — this notifier holds
  /// the default list, and the caller is looking at the archived one.
  Future<String?> unarchive(String conversationId) async {
    final result = await _chatService.unarchiveConversation(conversationId);
    return result.success ? null : ErrorStringsFor.fromString(result.error);
  }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/services/chat_archive_search_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/services/chat_service.dart lib/providers/chat_provider.dart \
        test/services/chat_archive_search_test.dart
git commit -m "feat(chat): archive and search service calls"
```

---

### Task 7: App — search screen

**Files:**
- Create: `APP lib/screens/chat/chat_search_screen.dart`
- Modify: `APP lib/screens/chat/matches_screen.dart`
- Test: `APP test/screens/chat/chat_search_screen_test.dart`

**Interfaces:**
- Consumes: `ChatService.searchMessages` (Task 6)
- Produces: `ChatSearchScreen`

Follows BananaTalk's `pages/chat/search/chat_search_screen.dart`: a 500ms debounce, results cleared the moment the query empties, and explicit loading and error states rather than a spinner that never resolves.

- [ ] **Step 1: Write the failing test**

Create `APP test/screens/chat/chat_search_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/chat/chat_search_screen.dart';

Message _msg(String id, String text) => Message.fromJson({
  'id': id,
  'sender_id': 'u1',
  'text': text,
  'type': 'text',
  'created_at': '2026-08-17T00:00:00.000Z',
});

void main() {
  testWidgets('does not search until typing settles', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: ChatSearchScreen(
        search: (q, {int limit = 20, int offset = 0}) async {
          calls++;
          return [_msg('m1', q)];
        },
      ),
    ));

    await tester.enterText(find.byType(TextField), 'h');
    await tester.enterText(find.byType(TextField), 'he');
    await tester.enterText(find.byType(TextField), 'hel');
    await tester.pump(const Duration(milliseconds: 100));

    expect(calls, 0, reason: 'a call per keystroke is 3 requests for one search');

    await tester.pump(const Duration(milliseconds: 600));
    expect(calls, 1);
  });

  testWidgets('shows results', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChatSearchScreen(
        search: (q, {int limit = 20, int offset = 0}) async =>
            [_msg('m1', 'found you')],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'found');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('found you'), findsOneWidget);
  });

  testWidgets('clearing the query clears the results without searching', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: ChatSearchScreen(
        search: (q, {int limit = 20, int offset = 0}) async {
          calls++;
          return [_msg('m1', 'found you')];
        },
      ),
    ));

    await tester.enterText(find.byType(TextField), 'found');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('found you'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('found you'), findsNothing);
    expect(calls, 1, reason: 'an empty query is not a search');
  });

  testWidgets('an empty result set says so rather than showing nothing', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: ChatSearchScreen(
        search: (q, {int limit = 20, int offset = 0}) async => [],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'nothing');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.textContaining('No messages'), findsOneWidget);
  });

  testWidgets('a failure is shown, not swallowed', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ChatSearchScreen(
        search: (q, {int limit = 20, int offset = 0}) async =>
            throw Exception('offline'),
      ),
    ));

    await tester.enterText(find.byType(TextField), 'boom');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.textContaining('Search failed'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/chat/chat_search_screen_test.dart`
Expected: FAIL — `Error when reading 'lib/screens/chat/chat_search_screen.dart'`

- [ ] **Step 3: Write the screen**

Create `APP lib/screens/chat/chat_search_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flame/models/models.dart';

/// Runs a search. Injectable so the screen is testable without a network.
typedef MessageSearch = Future<List<Message>> Function(
  String query, {
  int limit,
  int offset,
});

/// Search across every conversation the user can still open.
///
/// Debounced at 500ms, following BananaTalk's
/// `pages/chat/search/chat_search_screen.dart`: without it, a five-letter word
/// is five requests against a route rate limited to twenty a minute.
class ChatSearchScreen extends StatefulWidget {
  final MessageSearch search;

  const ChatSearchScreen({super.key, required this.search});

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Message> _results = [];
  bool _isLoading = false;
  String? _error;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();

    final query = raw.trim();
    if (query.isEmpty) {
      // Not a search. Clearing the box should clear the screen, not fire a
      // request for everything.
      setState(() {
        _results = [];
        _error = null;
        _isLoading = false;
        _searched = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () => _run(query));
  }

  Future<void> _run(String query) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await widget.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _isLoading = false;
        _searched = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Search failed. Please try again.';
        _isLoading = false;
        _searched = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search messages',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_searched && _results.isEmpty) {
      return const Center(child: Text('No messages found'));
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final m = _results[i];
        return ListTile(
          title: Text(m.content, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(m.timeText),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screens/chat/chat_search_screen_test.dart`
Expected: PASS — 5 tests

- [ ] **Step 5: Add the entry point**

In `APP lib/screens/chat/matches_screen.dart`, add a search icon to the `AppBar`
that pushes `ChatSearchScreen`, wiring `search:` to
`ref.read(chatServiceProvider).searchMessages` and unwrapping the
`ServiceResult` — throwing on failure so the screen's error branch renders.

- [ ] **Step 6: Run the app suite**

Run: `flutter test && flutter analyze`
Expected: all pass, 0 errors and 0 warnings.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/chat/chat_search_screen.dart lib/screens/chat/matches_screen.dart \
        test/screens/chat/chat_search_screen_test.dart
git commit -m "feat(chat): search screen with a debounced query"
```

---

### Task 8: App — archive UI

**Files:**
- Create: `APP lib/screens/chat/archived_conversations_screen.dart`
- Modify: `APP lib/screens/chat/matches_screen.dart`
- Test: `APP test/screens/chat/archive_ui_test.dart`

**Interfaces:**
- Consumes: `ConversationsNotifier.archive/unarchive` (Task 6)
- Produces: `ArchivedConversationsScreen`

- [ ] **Step 1: Write the failing test**

Create `APP test/screens/chat/archive_ui_test.dart` asserting:

```dart
// 1. Swiping a conversation tile calls archive() with that conversation's id.
// 2. The row disappears from the list after a successful archive.
// 3. A failed archive leaves the row in place and shows the error, rather than
//    hiding a conversation that is still there on the server.
// 4. ArchivedConversationsScreen renders an empty state when there are none.
```

Drive the notifier through a `ProviderContainer` override, following
`test/providers/conversations_realtime_test.dart`'s `_Seeded` pattern.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screens/chat/archive_ui_test.dart`
Expected: FAIL — `ArchivedConversationsScreen` is not defined

- [ ] **Step 3: Add swipe-to-archive**

In `matches_screen.dart`, wrap the tile returned by the conversations
`SliverChildBuilderDelegate`:

```dart
                      final conversation = conversations[index];
                      return Dismissible(
                        key: ValueKey(conversation.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: const Icon(Icons.archive, color: Colors.white),
                        ),
                        // confirmDismiss, not onDismissed: returning false on
                        // failure keeps a conversation on screen that is still
                        // there on the server. Dismissing first and reconciling
                        // later would show the user a lie.
                        confirmDismiss: (_) async {
                          final error = await ref
                              .read(conversationsProvider.notifier)
                              .archive(conversation.id);
                          if (error != null && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(error)),
                            );
                            return false;
                          }
                          return true;
                        },
                        child: _ConversationTile(conversation: conversation),
                      );
```

Note `archive()` already removes the row from the cached list, so the
`Dismissible` and the provider agree rather than racing.

- [ ] **Step 4: Write the archived list**

First add the parameter. In `APP lib/services/chat_service.dart`, give
`getConversations` a named `archived` flag, defaulting to false so every
existing caller is unaffected:

```dart
  Future<ServiceResult<List<Conversation>>> getConversations({
    int limit = 20,
    int offset = 0,
    bool archived = false,
  }) async {
    final response = await _apiClient.get(
      '/conversations?limit=$limit&offset=$offset&archived=$archived',
    );
    // ... existing parsing unchanged ...
  }
```

Then create `APP lib/screens/chat/archived_conversations_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/providers.dart';

/// The conversations the user archived.
///
/// This screen is not optional. `listConversations` hides archived
/// conversations from the default list, so without a way to see them archiving
/// would make a conversation unreachable — the messages still there, the user
/// unable to get to them.
class ArchivedConversationsScreen extends ConsumerStatefulWidget {
  const ArchivedConversationsScreen({super.key});

  @override
  ConsumerState<ArchivedConversationsScreen> createState() =>
      _ArchivedConversationsScreenState();
}

class _ArchivedConversationsScreenState
    extends ConsumerState<ArchivedConversationsScreen> {
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await ref
        .read(chatServiceProvider)
        .getConversations(archived: true);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result.success && result.data != null) {
        _conversations = result.data!;
        _error = null;
      } else {
        _error = result.error ?? 'Could not load archived chats';
      }
    });
  }

  Future<void> _unarchive(Conversation c) async {
    final error =
        await ref.read(conversationsProvider.notifier).unarchive(c.id);
    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _conversations.removeWhere((x) => x.id == c.id));
    // The default list is stale now that this conversation belongs in it.
    ref.read(conversationsProvider.notifier).loadConversations(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archived')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_conversations.isEmpty) {
      return const Center(child: Text('No archived chats'));
    }

    return ListView.builder(
      itemCount: _conversations.length,
      itemBuilder: (context, i) {
        final c = _conversations[i];
        return ListTile(
          title: Text(c.otherUser.name),
          subtitle: Text(
            c.lastMessagePreview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.unarchive_outlined),
            tooltip: 'Unarchive',
            onPressed: () => _unarchive(c),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 5: Add the entry point**

An "Archived" item in the Messages screen's overflow menu that pushes
`ArchivedConversationsScreen`.

- [ ] **Step 6: Run the app suite**

Run: `flutter test && flutter analyze`
Expected: all pass, 0 errors and 0 warnings.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/chat/archived_conversations_screen.dart \
        lib/screens/chat/matches_screen.dart lib/services/chat_service.dart \
        test/screens/chat/archive_ui_test.dart
git commit -m "feat(chat): swipe to archive, and a list to get it back"
```

---

### Task 9: End-to-end verification

**Files:** none — a manual gate.

- [ ] **Step 1: Full backend suite**

```bash
cd ~/Projects/BananaTalk/backend
node --test --test-concurrency=1 flame/__tests__/
```

Expected: everything passes except possibly ONE test, which is the known flake —
a different test each run, passing when run alone, and present on `main` too.
Re-run that single file to confirm before treating it as real.

- [ ] **Step 2: Full app suite**

```bash
cd ~/Desktop/Flame/flame_front_app
flutter test && flutter analyze
```

Expected: all pass, 0 errors and 0 warnings.

- [ ] **Step 3: Legacy index check before deploying**

```bash
cd ~/Projects/BananaTalk/backend
node flame/scripts/drop-legacy-indexes.js
```

Expected: `nothing to drop`. This project adds a `$text` index and a
`Translation` collection, and `flame_db` has held indexes from an earlier schema
that no test could see because `mongodb-memory-server` starts empty.

- [ ] **Step 4: Confirm the environment**

`LIBRETRANSLATE_URL` must be set in `config/config.env`. Without it the service
falls back to the public instance, which is rate limited and will reject
production traffic. Check the boot log for the warning the service emits.

- [ ] **Step 5: Verify by hand, two accounts**

1. A and B exchange a few messages, including one in another language.
2. A taps Translate on B's message — it translates. Tap again — instant, from cache.
3. A searches a word from the conversation — the message comes back.
4. A **blocks** B, then searches that same word — **nothing comes back.** This is
   the security rule; if it returns anything, stop and do not deploy.
5. A archives a conversation — it leaves the list, appears under Archived, and
   the other participant still sees it in theirs.
6. A unarchives it — it returns to the list.
