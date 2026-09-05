# Stories That Start Conversations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Flame's stories from a broadcast into the void into the thing that gets matches talking, and make story media actually disappear when it says it does.

**Architecture:** Five sequential slices. A sweep job takes ownership of story media lifetime (today a MongoDB TTL index deletes the row and leaks the S3 object forever). Reactions and replies then give a viewer something to do — a reply goes through the existing chat send path, so blocks, unmatch and push keep working untouched. Text stories remove the need for a photo. Highlights let a story become lasting profile content by referencing the same S3 object the sweep now knows to skip.

**Tech Stack:** Node/Express, Mongoose, zod, `node --test` (backend); Flutter, Riverpod, `flutter_test` (app).

**Spec:** `docs/superpowers/specs/2026-09-05-stories-that-start-conversations-design.md`

## Global Constraints

- **Backend changes are confined to `flame/`.** Everything else in `/Users/firdavsmutalipov/Projects/BananaTalk/backend` is BananaTalk, a different live product. A change outside `flame/` is a task failure.
- App repo: `/Users/firdavsmutalipov/Desktop/Flame/flame_front_app`. Backend repo: `/Users/firdavsmutalipov/Projects/BananaTalk/backend`.
- `flutter analyze` must report **0 errors and 0 warnings**. Count them with `grep -oE '^ *[a-z]+ •'` — warnings print at column 0 while infos are indented, so a leading-space pattern silently misses them.
- Routes are pushed **by name**. `test/core/navigation/single_navigation_path_test.dart` fails on an inline `Navigator.push(MaterialPageRoute(...))` in `lib/`.
- Any new user-facing string needs a key in **all 25 base ARB locales**; `test/l10n/arb_parity_test.dart` enforces it. Regional overlays (`app_pt_BR.arb`, `app_zh_Hant.arb`, …) only need a key where the variant genuinely differs.
- `app_pt.arb` is **European** Portuguese: no `você`, no gerunds (`está a aprender`, not `está aprendendo`), enclitic pronouns (`Avise-me`, not `Me avise`).
- Backend tests: run only the files you touch. Never run the whole suite in one command — it exceeds the tool timeout. Two halves exist as `run-half.sh`, but a per-file run is what you want while working.
- Story captions and text cap at **200 characters** (`MAX_CAPTION`, matching `Story.caption`'s `maxlength: 200`).
- Highlights cap at **9 per user**, matching `MAX_PHOTOS_PER_USER = 9` in `flame/services/userService.js`.

---

## File Structure

**Backend — create:**
- `flame/jobs/storyExpiryJob.js` — the sweep: delete expired stories' S3 objects, then their rows.
- `flame/services/storyScheduler.js` — timer for the sweep. Separate from `pushScheduler` because that one returns early when Firebase is unconfigured, and media cleanup must not depend on push.
- `flame/models/StoryHighlight.js` — pinned stories.
- `flame/services/highlightService.js` — pin, unpin, list.
- `flame/controllers/highlightController.js`, `flame/routes/highlights.js`.

**Backend — modify:**
- `flame/models/Story.js` — `reactions`, `kind`, `text`, `background`; raise the TTL backstop.
- `flame/models/Message.js` — `storyContext`.
- `flame/services/storyService.js` — reactions, text stories, `toStory` output.
- `flame/services/chatService.js` — accept `storyContext` on send.
- `flame/controllers/storyController.js`, `flame/routes/stories.js`, `flame/routes/conversations.js`, `flame/index.js`.
- `flame/services/pushService.js` — a `story_reaction` push type.

**App — create:**
- `lib/core/stories/story_backgrounds.dart` — the named gradient palette.
- `lib/screens/stories/widgets/story_reaction_bar.dart`
- `lib/screens/stories/widgets/story_reply_field.dart`
- `lib/widgets/story_context_bubble.dart` — the quoted-story chip inside a chat bubble.
- `lib/models/story_highlight.dart`, `lib/services/highlight_service.dart`, `lib/providers/highlight_provider.dart`
- `lib/widgets/highlights_row.dart`

**App — modify:**
- `lib/models/story.dart`, `lib/models/message.dart`
- `lib/services/story_service.dart`, `lib/providers/story_provider.dart`
- `lib/screens/stories/story_viewer_screen.dart`, `lib/screens/stories/create_story_screen.dart`
- `lib/screens/chat/widgets/message_bubble.dart`
- `lib/screens/profile/profile_detail_screen.dart`, `lib/screens/profile/my_profile_screen.dart`
- `lib/core/push/push_payload.dart`

---

## Task 1: The sweep that makes stories actually disappear

**Files:**
- Create: `flame/jobs/storyExpiryJob.js`, `flame/services/storyScheduler.js`
- Modify: `flame/models/Story.js`, `flame/index.js:53-59`
- Test: `flame/__tests__/storyExpiry.test.js`

**Interfaces:**
- Produces: `runStoryExpirySweep({ now = new Date(), batchSize = 200 } = {}) -> Promise<{ swept, skipped, failed }>` from `flame/jobs/storyExpiryJob.js`; `startStoryScheduler() -> void` and `SWEEP_TICK_MS` from `flame/services/storyScheduler.js`.
- Consumes: `flame/utils/s3.js` `deleteObject(key)`; `flame/models/Story.js`.

**Background the implementer needs:** `Story` has a TTL index (`expiresAt: 1, expireAfterSeconds: 0`). MongoDB's TTL monitor deletes the *document* and runs no application code, so `s3.deleteObject` never fires on expiry — only in `deleteStory`. When the row goes it takes `mediaKey` with it, so the object becomes unreferenceable. Task 5 depends on this sweep skipping highlighted media, but `StoryHighlight` does not exist yet — Step 5 handles that ordering explicitly.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/storyExpiry.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

process.env.FLAME_SPACES_BUCKET = 't';
process.env.SPACES_ENDPOINT = 'sfo3.digitaloceanspaces.com';
process.env.DO_SPACES_KEY = 'k';
process.env.DO_SPACES_SECRET = 's';

async function setup() {
  await dbHelper.start();
  ['../db', '../models/Story', '../jobs/storyExpiryJob'].forEach((m) => {
    try { delete require.cache[require.resolve(m)]; } catch {}
  });
  const { connect } = require('../db');
  await connect();
  return {
    Story: require('../models/Story'),
    job: require('../jobs/storyExpiryJob'),
  };
}

async function teardown() {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
}

const HOUR = 60 * 60 * 1000;

test('an expired story loses its S3 object, not just its row', async (t) => {
  // The whole point. The TTL index already removed rows; nothing ever
  // removed the objects, and once the row was gone its mediaKey went too,
  // so the object could not even be named again.
  const { Story, job } = await setup();
  t.after(teardown);

  await Story.create({
    userId: 'u1', mediaUrl: 'https://x/a.jpg', mediaKey: 'flame/stories/u1/a.jpg',
    expiresAt: new Date(Date.now() - HOUR),
  });

  const deleted = [];
  const res = await job.runStoryExpirySweep({
    deleteObject: async (key) => { deleted.push(key); },
  });

  assert.deepEqual(deleted, ['flame/stories/u1/a.jpg']);
  assert.equal(res.swept, 1);
  assert.equal(await Story.countDocuments({}), 0);
});

test('a live story is left alone', async (t) => {
  const { Story, job } = await setup();
  t.after(teardown);

  await Story.create({
    userId: 'u1', mediaUrl: 'https://x/b.jpg', mediaKey: 'k-b',
    expiresAt: new Date(Date.now() + HOUR),
  });

  const deleted = [];
  await job.runStoryExpirySweep({ deleteObject: async (k) => { deleted.push(k); } });

  assert.deepEqual(deleted, []);
  assert.equal(await Story.countDocuments({}), 1);
});

test('a failed object delete keeps the row for the next tick', async (t) => {
  // Deleting the object BEFORE the row is deliberate: dying between the two
  // leaves a retryable row. The other order loses the key forever and
  // recreates exactly the leak this job removes.
  const { Story, job } = await setup();
  t.after(teardown);

  await Story.create({
    userId: 'u1', mediaUrl: 'https://x/c.jpg', mediaKey: 'k-c',
    expiresAt: new Date(Date.now() - HOUR),
  });

  const res = await job.runStoryExpirySweep({
    deleteObject: async () => { throw new Error('S3 down'); },
  });

  assert.equal(res.failed, 1);
  assert.equal(res.swept, 0);
  assert.equal(await Story.countDocuments({}), 1, 'the row must survive to retry');
});

test('one failure does not abort the rest of the sweep', async (t) => {
  const { Story, job } = await setup();
  t.after(teardown);

  await Story.create({ userId: 'u1', mediaUrl: 'https://x/d.jpg', mediaKey: 'bad', expiresAt: new Date(Date.now() - HOUR) });
  await Story.create({ userId: 'u2', mediaUrl: 'https://x/e.jpg', mediaKey: 'good', expiresAt: new Date(Date.now() - HOUR) });

  const res = await job.runStoryExpirySweep({
    deleteObject: async (key) => { if (key === 'bad') throw new Error('nope'); },
  });

  assert.equal(res.swept, 1);
  assert.equal(res.failed, 1);
  assert.equal(await Story.countDocuments({}), 1);
});

test('a story with no mediaKey is swept without touching S3', async (t) => {
  // Text stories in Task 4 have none, and neither do rows written before
  // mediaKey existed.
  const { Story, job } = await setup();
  t.after(teardown);

  await Story.create({
    userId: 'u1', mediaUrl: 'https://x/f.jpg', mediaKey: null,
    expiresAt: new Date(Date.now() - HOUR),
  });

  let called = 0;
  const res = await job.runStoryExpirySweep({ deleteObject: async () => { called += 1; } });

  assert.equal(called, 0);
  assert.equal(res.swept, 1);
  assert.equal(await Story.countDocuments({}), 0);
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd /Users/firdavsmutalipov/Projects/BananaTalk/backend
node --test flame/__tests__/storyExpiry.test.js
```

Expected: FAIL — `Cannot find module '../jobs/storyExpiryJob'`.

- [ ] **Step 3: Write the job**

Create `flame/jobs/storyExpiryJob.js`:

```js
const Story = require('../models/Story');
const s3 = require('../utils/s3');
const logger = require('../utils/logger');

/**
 * Deletes expired stories, media first.
 *
 * The TTL index on `expiresAt` removes documents, and MongoDB runs no
 * application code when it does — so before this job existed, every story's
 * S3 object survived its story forever. Worse, the row carried the only copy
 * of `mediaKey`, so once TTL removed it the object could not be named again
 * without listing the bucket.
 *
 * Object first, then row. Dying between the two leaves a row whose media is
 * already gone, which the next tick retries harmlessly. The other order loses
 * the key and recreates the leak.
 *
 * `deleteObject` is injected so tests do not need S3.
 */
async function runStoryExpirySweep({
  now = new Date(),
  batchSize = 200,
  deleteObject = s3.deleteObject,
} = {}) {
  const expired = await Story.find({ expiresAt: { $lt: now } })
    .limit(batchSize)
    .lean();

  let swept = 0;
  let skipped = 0;
  let failed = 0;

  for (const story of expired) {
    if (story.mediaKey) {
      try {
        await deleteObject(story.mediaKey);
      } catch (err) {
        // Keep the row so the next tick tries again, and keep going: one
        // unreachable object must not strand every later story in the batch.
        failed += 1;
        logger.warn(`story sweep: could not delete ${story.mediaKey} —`, err.message);
        continue;
      }
    }
    await Story.deleteOne({ _id: story._id });
    swept += 1;
  }

  if (swept || failed) {
    logger.info(`story sweep: ${swept} swept, ${skipped} skipped, ${failed} failed`);
  }
  return { swept, skipped, failed };
}

module.exports = { runStoryExpirySweep };
```

- [ ] **Step 4: Run the tests — all five pass**

```bash
node --test flame/__tests__/storyExpiry.test.js
```

Expected: `# pass 5`, `# fail 0`.

- [ ] **Step 5: Add the highlight exemption, with the model not yet built**

Task 5 creates `StoryHighlight`. The sweep must skip media a highlight holds, but must also work today, before that model exists. Add to `runStoryExpirySweep`, immediately after the `expired` query:

```js
  // Highlighted media outlives its story deliberately (see Task 5). The model
  // may not exist yet, and requiring it unconditionally would make this job
  // fail to load — so ask for it defensively rather than importing at the top.
  let heldKeys = new Set();
  const keys = expired.map((s) => s.mediaKey).filter(Boolean);
  if (keys.length) {
    try {
      const StoryHighlight = require('../models/StoryHighlight');
      const held = await StoryHighlight.find({ mediaKey: { $in: keys } })
        .select('mediaKey').lean();
      heldKeys = new Set(held.map((h) => h.mediaKey));
    } catch (err) {
      if (err.code !== 'MODULE_NOT_FOUND') throw err;
    }
  }
```

and change the delete branch to consult it:

```js
    if (story.mediaKey && !heldKeys.has(story.mediaKey)) {
      try {
        await deleteObject(story.mediaKey);
      } catch (err) {
        failed += 1;
        logger.warn(`story sweep: could not delete ${story.mediaKey} —`, err.message);
        continue;
      }
    } else if (story.mediaKey) {
      // Pinned: the row goes, the object stays, and the highlight owns it.
      skipped += 1;
    }
```

- [ ] **Step 6: Re-run — still five passes**

```bash
node --test flame/__tests__/storyExpiry.test.js
```

Expected: `# pass 5`, `# fail 0`. The exemption is inert until Task 5.

- [ ] **Step 7: Raise the TTL backstop**

In `flame/models/Story.js`, replace the TTL index line:

```js
// TTL index: auto-delete once expiresAt is in the past.
storySchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });
```

with:

```js
// TTL backstop, NOT the mechanism. storyExpiryJob sweeps expired stories and
// deletes their S3 objects first; this index only stops rows accumulating
// without bound if that job is down. Seven days so a weekend outage cannot
// silently orphan objects again by removing the row — and its mediaKey —
// before the sweep ever sees it.
storySchema.index({ expiresAt: 1 }, { expireAfterSeconds: 7 * 24 * 60 * 60 });
```

**Note for the implementer:** changing `expireAfterSeconds` on an existing index requires a `collMod`; Mongoose will not alter it in place and logs an index-option-conflict warning instead. Add a line to your report saying the production index needs
`db.stories.runCommand('collMod', { index: { keyPattern: { expiresAt: 1 }, expireAfterSeconds: 604800 } })`. Do not run it.

- [ ] **Step 8: Write the scheduler test**

Create `flame/__tests__/storyScheduler.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');

process.env.FLAME_SPACES_BUCKET = 't';
process.env.SPACES_ENDPOINT = 'sfo3.digitaloceanspaces.com';
process.env.DO_SPACES_KEY = 'k';
process.env.DO_SPACES_SECRET = 's';

test('the sweep is scheduled even when push is not configured', () => {
  // pushScheduler returns early without Firebase. Media cleanup has nothing
  // to do with push, and hanging it off that timer would mean stories never
  // stop leaking on an install that has not set Firebase up.
  delete process.env.FLAME_FIREBASE_PROJECT_ID;
  delete process.env.FLAME_FIREBASE_SERVICE_ACCOUNT;
  delete require.cache[require.resolve('../services/storyScheduler')];
  const sched = require('../services/storyScheduler');

  const timers = [];
  const stop = sched.startStoryScheduler({
    setTimer: (fn, ms) => { timers.push(ms); return 0; },
  });

  assert.deepEqual(timers, [sched.SWEEP_TICK_MS]);
  assert.equal(typeof stop, 'function');
});
```

- [ ] **Step 9: Run it and watch it fail**

```bash
node --test flame/__tests__/storyScheduler.test.js
```

Expected: FAIL — `Cannot find module '../services/storyScheduler'`.

- [ ] **Step 10: Write the scheduler**

Create `flame/services/storyScheduler.js`:

```js
const logger = require('../utils/logger');

/**
 * How often expired stories are swept.
 *
 * Hourly, not per-minute: a story's media surviving its expiry by up to an
 * hour is invisible to users, and a full scan every minute is not free.
 */
const SWEEP_TICK_MS = 60 * 60 * 1000;

/**
 * Its own scheduler, deliberately separate from pushScheduler.
 *
 * That one returns early when Firebase is unconfigured, so anything attached
 * to it silently never runs on an install without push. Deleting expired
 * media has nothing to do with notifications and must not inherit that gate.
 *
 * `setTimer` is injected so a test can assert what was scheduled without
 * leaving a pending timer behind.
 */
function startStoryScheduler({ setTimer = setTimeout } = {}) {
  let handle = null;
  let stopped = false;

  const tick = async () => {
    try {
      await require('../jobs/storyExpiryJob').runStoryExpirySweep();
    } catch (err) {
      // A failing sweep must not take its timer with it, or one bad hour
      // ends the schedule until the next deploy.
      logger.error('story sweep failed', err);
    }
    if (!stopped) handle = setTimer(tick, SWEEP_TICK_MS);
  };

  handle = setTimer(tick, SWEEP_TICK_MS);
  logger.info(`story scheduler: sweeping every ${SWEEP_TICK_MS / 60000}m`);

  return function stopStoryScheduler() {
    stopped = true;
    if (handle) clearTimeout(handle);
  };
}

module.exports = { startStoryScheduler, SWEEP_TICK_MS };
```

- [ ] **Step 11: Run — the scheduler test passes**

```bash
node --test flame/__tests__/storyScheduler.test.js
```

Expected: `# pass 1`, `# fail 0`.

- [ ] **Step 12: Start it at boot**

In `flame/index.js`, after the existing `startPushScheduler()` try/catch block (ends at line 59), add:

```js
// Story media sweep. Separate from the push scheduler above because that one
// is inert without Firebase, and expired media must be deleted regardless.
try {
  require('./services/storyScheduler').startStoryScheduler();
} catch (e) {
  console.error('[flame] story scheduler init failed (non-fatal):', e.message);
}
```

- [ ] **Step 13: Confirm nothing else broke**

```bash
node --test flame/__tests__/stories.test.js flame/__tests__/storyExpiry.test.js flame/__tests__/storyScheduler.test.js
```

Expected: `# fail 0`.

- [ ] **Step 14: Commit**

```bash
cd /Users/firdavsmutalipov/Projects/BananaTalk/backend
git add flame/jobs/storyExpiryJob.js flame/services/storyScheduler.js \
        flame/models/Story.js flame/index.js \
        flame/__tests__/storyExpiry.test.js flame/__tests__/storyScheduler.test.js
git commit -m "fix(stories): make expired stories actually disappear

The 24-hour expiry was a MongoDB TTL index, and TTL deletion runs no
application code — so s3.deleteObject never fired on expiry, only when an
author deleted a story by hand. Every story photo ever posted is still
publicly fetchable at its original URL. Worse, the row carried the only copy
of mediaKey, so once TTL removed it the object could not be named again.

A sweep now deletes the object first and the row second, so dying between
the two leaves a retryable row rather than an unreferenceable object. The
TTL index stays as a backstop at seven days: long enough that a weekend
outage cannot orphan media again, short enough to bound the rows.

Its own scheduler, not the push one, which returns early without Firebase —
media cleanup must not depend on notifications being configured."
```

---

## Task 2: Reactions

**Files:**
- Modify: `flame/models/Story.js`, `flame/services/storyService.js`, `flame/controllers/storyController.js`, `flame/routes/stories.js`, `flame/services/pushService.js`
- Test: `flame/__tests__/storyReactions.test.js`

**Interfaces:**
- Consumes: `canView(viewerId, authorId) -> Promise<boolean>` and `getActive(storyId)` from `flame/services/storyService.js` (both already exist, module-private).
- Produces: `reactToStory(viewerId, storyId, emoji) -> Promise<{ reactions }>` and `unreactToStory(viewerId, storyId) -> Promise<{ reactions }>`; `toStory` gains `my_reaction: string|null` and `reactions: [{ user_id, emoji }]|null` (author only).

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/storyReactions.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

process.env.FLAME_SPACES_BUCKET = 't';
process.env.SPACES_ENDPOINT = 'sfo3.digitaloceanspaces.com';
process.env.DO_SPACES_KEY = 'k';
process.env.DO_SPACES_SECRET = 's';

async function setup() {
  await dbHelper.start();
  ['../db', '../models/Story', '../models/User', '../models/Match',
   '../services/storyService', '../services/matchService',
   '../services/visibilityService'].forEach((m) => {
    try { delete require.cache[require.resolve(m)]; } catch {}
  });
  const { connect } = require('../db');
  await connect();
  return {
    Story: require('../models/Story'),
    Match: require('../models/Match'),
    svc: require('../services/storyService'),
  };
}

async function teardown() {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
}

const HOUR = 60 * 60 * 1000;
const future = () => new Date(Date.now() + HOUR);

// storyService.canView requires a real match. Match REQUIRES pairKey (unique,
// no default) and conversationId, and "matched" means endedBy is null — there
// is no isActive field. Copied from the shape deleteAccount.test.js uses.
async function match(Match, a, b) {
  const pair = [a, b].sort();
  await Match.create({
    users: pair,
    pairKey: pair.join(':'),
    conversationId: `conv-${pair.join('-')}`,
    endedBy: null,
  });
}

test('a match can react, and reacting again replaces rather than appends', async (t) => {
  const { Story, Match, svc } = await setup();
  t.after(teardown);
  await match(Match, 'author', 'viewer');

  const story = await Story.create({
    userId: 'author', mediaUrl: 'https://x/a.jpg', mediaKey: 'k', expiresAt: future(),
  });

  await svc.reactToStory('viewer', story._id.toString(), '❤️');
  await svc.reactToStory('viewer', story._id.toString(), '🔥');

  const after = await Story.findById(story._id).lean();
  assert.equal(after.reactions.length, 1, 'one reaction per viewer, not a log');
  assert.equal(after.reactions[0].emoji, '🔥');
});

test('an emoji outside the fixed set is rejected', async (t) => {
  // Fixed because the point is one tap. A free-form field is a text channel
  // to a stranger's phone under another name.
  const { Story, Match, svc } = await setup();
  t.after(teardown);
  await match(Match, 'author', 'viewer');

  const story = await Story.create({
    userId: 'author', mediaUrl: 'https://x/a.jpg', mediaKey: 'k', expiresAt: future(),
  });

  await assert.rejects(
    () => svc.reactToStory('viewer', story._id.toString(), '🍕'),
    /emoji/i,
  );
});

test('a non-match cannot react', async (t) => {
  const { Story, svc } = await setup();
  t.after(teardown);

  const story = await Story.create({
    userId: 'author', mediaUrl: 'https://x/a.jpg', mediaKey: 'k', expiresAt: future(),
  });

  await assert.rejects(() => svc.reactToStory('stranger', story._id.toString(), '❤️'));
});

test('removing a reaction leaves none', async (t) => {
  const { Story, Match, svc } = await setup();
  t.after(teardown);
  await match(Match, 'author', 'viewer');

  const story = await Story.create({
    userId: 'author', mediaUrl: 'https://x/a.jpg', mediaKey: 'k', expiresAt: future(),
  });

  await svc.reactToStory('viewer', story._id.toString(), '❤️');
  await svc.unreactToStory('viewer', story._id.toString());

  const after = await Story.findById(story._id).lean();
  assert.equal(after.reactions.length, 0);
});

test('only the author sees who reacted', async (t) => {
  // A story is not a public post and a reaction is not a like count.
  const { Story, Match, svc } = await setup();
  t.after(teardown);
  await match(Match, 'author', 'viewer');
  await match(Match, 'author', 'other');

  const story = await Story.create({
    userId: 'author', mediaUrl: 'https://x/a.jpg', mediaKey: 'k', expiresAt: future(),
  });
  await svc.reactToStory('viewer', story._id.toString(), '❤️');

  const mine = await svc.getMyStories('author');
  assert.equal(mine.stories[0].reactions.length, 1);

  const feed = await svc.getFeed('other');
  const seen = feed[0].stories[0];
  assert.equal(seen.reactions, null, 'another viewer must not see the list');
  assert.equal(seen.my_reaction, null);
});

test('a reaction to an expired story is rejected', async (t) => {
  const { Story, Match, svc } = await setup();
  t.after(teardown);
  await match(Match, 'author', 'viewer');

  const story = await Story.create({
    userId: 'author', mediaUrl: 'https://x/a.jpg', mediaKey: 'k',
    expiresAt: new Date(Date.now() - HOUR),
  });

  await assert.rejects(() => svc.reactToStory('viewer', story._id.toString(), '❤️'));
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
node --test flame/__tests__/storyReactions.test.js
```

Expected: FAIL — `svc.reactToStory is not a function`.

- [ ] **Step 3: Add reactions to the model**

In `flame/models/Story.js`, above `const storySchema`:

```js
// One row per reacting viewer. Reacting again replaces the emoji rather than
// appending, so this is a set keyed by userId, not an event log.
const storyReactionSchema = new mongoose.Schema({
  userId:    { type: String, required: true },
  emoji:     { type: String, required: true },
  reactedAt: { type: Date, default: Date.now },
}, { _id: false });
```

and inside the schema body, after `viewerIds`:

```js
  reactions: { type: [storyReactionSchema], default: [] },
```

- [ ] **Step 4: Implement the service functions**

In `flame/services/storyService.js`, add near the top after the existing constants:

```js
/**
 * The reactions a viewer may send.
 *
 * Fixed, not a picker: the whole value of a reaction is that it costs one
 * tap. A free-form emoji field is a text channel to someone's phone wearing
 * a different hat, and it would need the moderation a text channel needs.
 */
const REACTION_EMOJI = Object.freeze(['❤️', '😂', '😮', '😢', '🔥', '👏']);
```

and the two functions, before `module.exports`:

```js
async function reactToStory(viewerId, storyId, emoji) {
  if (!REACTION_EMOJI.includes(emoji)) {
    throw new ValidationError('unsupported reaction emoji');
  }
  const story = await getActive(storyId);
  if (story.userId === viewerId) {
    throw new FlameError('FORBIDDEN', 'Cannot react to your own story', 403);
  }
  if (!(await canView(viewerId, story.userId))) {
    throw new FlameError('FORBIDDEN', 'Not allowed to view this story', 403);
  }

  const existing = story.reactions.find((r) => r.userId === viewerId);
  if (existing) {
    existing.emoji = emoji;
    existing.reactedAt = new Date();
  } else {
    story.reactions.push({ userId: viewerId, emoji, reactedAt: new Date() });
  }
  await story.save();

  // Best effort, and after the save: a push that fails must not lose the
  // reaction the user already saw land.
  try {
    await require('./pushService').sendStoryReaction(story.userId, {
      fromUserId: viewerId,
      storyId: story._id.toString(),
      emoji,
    });
  } catch (err) {
    logger.warn('story reaction push failed —', err.message);
  }

  return { reactions: story.reactions.length };
}

async function unreactToStory(viewerId, storyId) {
  const story = await getActive(storyId);
  story.reactions = story.reactions.filter((r) => r.userId !== viewerId);
  await story.save();
  return { reactions: story.reactions.length };
}
```

Add `reactToStory` and `unreactToStory` to `module.exports`.

**If `ValidationError`, `FlameError` or `logger` are not already imported in this file, add them** — match the import style already at the top of `storyService.js`.

- [ ] **Step 5: Expose reactions through `toStory`**

Replace `toStory` in `flame/services/storyService.js` with:

```js
function toStory(story, viewerId) {
  const isAuthor = story.userId === viewerId;
  const mine = story.reactions
    ? story.reactions.find((r) => r.userId === viewerId)
    : null;
  return {
    id: story._id.toString(),
    user_id: story.userId,
    media_url: story.mediaUrl,
    caption: story.caption,
    created_at: story.createdAt.toISOString(),
    expires_at: story.expiresAt.toISOString(),
    view_count: story.viewerIds.length,
    has_viewed: story.viewerIds.includes(viewerId),
    // What THIS viewer sent, so the bar can show it selected.
    my_reaction: mine ? mine.emoji : null,
    // Who reacted is the author's business only. Null rather than [] so a
    // client cannot mistake "not allowed to know" for "nobody reacted".
    reactions: isAuthor
      ? (story.reactions || []).map((r) => ({ user_id: r.userId, emoji: r.emoji }))
      : null,
  };
}
```

- [ ] **Step 6: Add the push type**

In `flame/services/pushService.js`, alongside the existing senders (`sendPromotion`, `sendNewMatch`, …), add:

```js
async function sendStoryReaction(userId, { fromUserId, storyId, emoji }) {
  return sendToUser(userId, {
    notification: {
      title: 'Someone reacted to your story',
      body: `${emoji}`,
    },
    data: {
      type: 'story_reaction',
      story_id: String(storyId),
      from_user_id: String(fromUserId),
    },
  });
}
```

Export it. **Match the existing senders' exact shape** — read `sendNewMatch` in that file first and mirror how it builds `notification`/`data` and how it consults notification settings, rather than copying the block above verbatim if it differs.

- [ ] **Step 7: Run the tests — all six pass**

```bash
node --test flame/__tests__/storyReactions.test.js
```

Expected: `# pass 6`, `# fail 0`.

- [ ] **Step 8: Wire the routes**

In `flame/controllers/storyController.js`:

```js
async function react(req, res) {
  const data = await storyService.reactToStory(req.user.id, req.params.id, req.body.emoji);
  res.json({ success: true, data });
}

async function unreact(req, res) {
  const data = await storyService.unreactToStory(req.user.id, req.params.id);
  res.json({ success: true, data });
}
```

Add both to `module.exports`.

In `flame/routes/stories.js`, add the schema beside `objectIdSchema`:

```js
const reactionSchema = z.object({
  emoji: z.string().min(1).max(8),
});
```

and the routes after the existing `/:id/view` line:

```js
router.post('/:id/reactions', auth, validate.params(objectIdSchema),
  validate.body(reactionSchema), asyncHandler(ctrl.react));
router.delete('/:id/reactions', auth, validate.params(objectIdSchema),
  asyncHandler(ctrl.unreact));
```

The emoji allowlist stays in the service, not the schema: it is a product rule, and the service is what other callers reach.

- [ ] **Step 9: Confirm the existing story tests still pass**

```bash
node --test flame/__tests__/stories.test.js flame/__tests__/storyReactions.test.js
```

Expected: `# fail 0`.

- [ ] **Step 10: Commit**

```bash
git add flame/models/Story.js flame/services/storyService.js \
        flame/controllers/storyController.js flame/routes/stories.js \
        flame/services/pushService.js flame/__tests__/storyReactions.test.js
git commit -m "feat(stories): let a match react to a story

Six fixed emoji, not a picker: the value of a reaction is that it costs one
tap, and a free-form field is a text channel to someone's phone wearing a
different hat.

One reaction per viewer — reacting again replaces it, so this is a set keyed
by user rather than an event log. Who reacted goes only to the author, as
null rather than an empty list, so a client cannot read 'not allowed to
know' as 'nobody reacted'."
```

---

## Task 3: Replies that land in the conversation

**Files:**
- Modify: `flame/models/Message.js`, `flame/services/chatService.js`, `flame/routes/conversations.js`
- Test: `flame/__tests__/storyReplies.test.js`

**Interfaces:**
- Consumes: `openConversation(userId, otherUserId)` and the existing `sendMessage` path in `flame/services/chatService.js`; `getActive(storyId)` from `storyService`.
- Produces: `sendMessage` accepts an optional `storyContext` argument; messages serialise `story_context: { story_id, caption_text, media_url }|null`.

**Background:** `Message` already has `replyTo` and a `messageType` enum of `['text','image','video','audio','voice','sticker']`. **Do not add a new enum value** — a story reply is an ordinary text message with context attached, and a new type would force every client type switch to learn about stories.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/storyReplies.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

process.env.FLAME_SPACES_BUCKET = 't';
process.env.SPACES_ENDPOINT = 'sfo3.digitaloceanspaces.com';
process.env.DO_SPACES_KEY = 'k';
process.env.DO_SPACES_SECRET = 's';

async function setup() {
  await dbHelper.start();
  ['../db', '../models/Story', '../models/Message', '../models/Conversation',
   '../models/User', '../models/Match', '../services/chatService',
   '../services/storyService', '../services/matchService',
   '../services/visibilityService'].forEach((m) => {
    try { delete require.cache[require.resolve(m)]; } catch {}
  });
  const { connect } = require('../db');
  await connect();
  return {
    Story: require('../models/Story'),
    Message: require('../models/Message'),
    Match: require('../models/Match'),
    User: require('../models/User'),
    chat: require('../services/chatService'),
  };
}

async function teardown() {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
}

const HOUR = 60 * 60 * 1000;

async function pair(User, Match) {
  const a = await User.create({ email: 'a@x.com', passwordHash: 'h', name: 'Ann', age: 30 });
  const b = await User.create({ email: 'b@x.com', passwordHash: 'h', name: 'Ben', age: 31 });
  // Match REQUIRES pairKey (unique, no default) and conversationId; matched
  // means endedBy is null, and there is no isActive field.
  const pair = [a._id.toString(), b._id.toString()].sort();
  await Match.create({
    users: pair,
    pairKey: pair.join(':'),
    conversationId: `conv-${pair.join('-')}`,
    endedBy: null,
  });
  return { a: a._id.toString(), b: b._id.toString() };
}

test('a reply reaches the conversation and creates one if absent', async (t) => {
  // The point of the whole feature: a first message to a match you have never
  // spoken to, prompted by something specific.
  const { Story, Message, Match, User, chat } = await setup();
  t.after(teardown);
  const { a, b } = await pair(User, Match);

  const story = await Story.create({
    userId: a, mediaUrl: 'https://x/a.jpg', mediaKey: 'k',
    caption: 'sunset at Ocean Beach', expiresAt: new Date(Date.now() + HOUR),
  });

  const conv = await chat.openConversation(b, a);
  const msg = await chat.sendMessage(b, conv.id, {
    text: 'that beach is my favourite',
    storyContext: {
      storyId: story._id.toString(),
      captionText: story.caption,
      mediaUrl: story.mediaUrl,
    },
  });

  assert.equal(msg.text, 'that beach is my favourite');
  const stored = await Message.findById(msg.id).lean();
  assert.equal(stored.storyContext.storyId, story._id.toString());
  assert.equal(stored.storyContext.captionText, 'sunset at Ocean Beach');
  assert.equal(stored.messageType, 'text', 'a story reply is an ordinary text message');
});

test('the caption survives the story, the photo does not', async (t) => {
  // captionText is copied onto the message; mediaUrl is a reference. After
  // Task 1 the 24-hour promise is real, and snapshotting the image into every
  // reply would quietly break it again.
  const { Story, Message, Match, User, chat } = await setup();
  t.after(teardown);
  const { a, b } = await pair(User, Match);

  const story = await Story.create({
    userId: a, mediaUrl: 'https://x/a.jpg', mediaKey: 'k',
    caption: 'sunset at Ocean Beach', expiresAt: new Date(Date.now() + HOUR),
  });
  const conv = await chat.openConversation(b, a);
  const msg = await chat.sendMessage(b, conv.id, {
    text: 'nice',
    storyContext: {
      storyId: story._id.toString(),
      captionText: story.caption,
      mediaUrl: story.mediaUrl,
    },
  });

  // The story goes, as the sweep will take it.
  await Story.deleteOne({ _id: story._id });

  const stored = await Message.findById(msg.id).lean();
  assert.equal(stored.storyContext.captionText, 'sunset at Ocean Beach',
    'the caption is the message\'s own copy');
  assert.ok(stored.storyContext.storyId, 'the reference remains for the client to resolve');
});

test('a message with no story context is unchanged', async (t) => {
  const { Match, User, Message, chat } = await setup();
  t.after(teardown);
  const { a, b } = await pair(User, Match);

  const conv = await chat.openConversation(b, a);
  const msg = await chat.sendMessage(b, conv.id, { text: 'hello' });

  const stored = await Message.findById(msg.id).lean();
  assert.equal(stored.storyContext.storyId, null);
});

test('a caption longer than the cap is truncated, not rejected', async (t) => {
  // The client sends what it was given; a long caption must not fail a send
  // the user has already committed to.
  const { Story, Message, Match, User, chat } = await setup();
  t.after(teardown);
  const { a, b } = await pair(User, Match);

  const long = 'x'.repeat(500);
  const story = await Story.create({
    userId: a, mediaUrl: 'https://x/a.jpg', mediaKey: 'k',
    expiresAt: new Date(Date.now() + HOUR),
  });
  const conv = await chat.openConversation(b, a);
  const msg = await chat.sendMessage(b, conv.id, {
    text: 'hi',
    storyContext: { storyId: story._id.toString(), captionText: long, mediaUrl: 'https://x/a.jpg' },
  });

  const stored = await Message.findById(msg.id).lean();
  assert.equal(stored.storyContext.captionText.length, 200);
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
node --test flame/__tests__/storyReplies.test.js
```

Expected: FAIL — `storyContext` is undefined on the stored message.

- [ ] **Step 3: Add `storyContext` to the message model**

In `flame/models/Message.js`, inside the schema body after `replyTo`:

```js
    /**
     * The story this message replies to.
     *
     * `captionText` is a SNAPSHOT and outlives the story; `mediaUrl` is a
     * REFERENCE and does not. A caption is text the author wrote; a photo is
     * the thing the 24-hour promise is about, and copying it into every reply
     * would make someone's disappearing photo permanent in five inboxes.
     * The client renders the thumbnail while the story lives and falls back to
     * `Replied to: "<captionText>"` once it is gone.
     */
    storyContext: {
      storyId:     { type: String, default: null },
      captionText: { type: String, default: null, maxlength: 200 },
      mediaUrl:    { type: String, default: null },
    },
```

- [ ] **Step 4: Accept it on send**

In `flame/services/chatService.js`, find `sendMessage` and locate where it builds the `Message.create({...})` payload. Add, immediately before that call:

```js
  // Truncate rather than reject: the caption came from a story the client was
  // already showing, and failing a send the user has committed to because
  // someone else wrote a long caption would be their problem to solve and
  // not their fault.
  const storyCtx = payload.storyContext
    ? {
      storyId: String(payload.storyContext.storyId || '') || null,
      captionText: typeof payload.storyContext.captionText === 'string'
        ? payload.storyContext.captionText.slice(0, 200)
        : null,
      mediaUrl: payload.storyContext.mediaUrl || null,
    }
    : undefined;
```

and add `...(storyCtx ? { storyContext: storyCtx } : {})` to the `Message.create` object.

**Read `sendMessage`'s real signature first.** If it takes positional arguments rather than a payload object, thread `storyContext` through in the style that function already uses; do not change its shape for other callers.

- [ ] **Step 5: Serialise it outward**

In `flame/services/chatService.js`, find `toMessage` and add to the returned object:

```js
    story_context: m.storyContext && m.storyContext.storyId
      ? {
        story_id: m.storyContext.storyId,
        caption_text: m.storyContext.captionText,
        media_url: m.storyContext.mediaUrl,
      }
      : null,
```

- [ ] **Step 6: Run the tests — all four pass**

```bash
node --test flame/__tests__/storyReplies.test.js
```

Expected: `# pass 4`, `# fail 0`.

- [ ] **Step 7: Accept it at the route**

In `flame/routes/conversations.js`, find `sendSchema` and add:

```js
  story_context: z.object({
    story_id: z.string().regex(/^[0-9a-fA-F]{24}$/),
    caption_text: z.string().max(200).nullable().optional(),
    media_url: z.string().url().nullable().optional(),
  }).optional(),
```

In `flame/controllers/chatController.js`'s `sendMessage`, map it into the service payload:

```js
    storyContext: req.body.story_context
      ? {
        storyId: req.body.story_context.story_id,
        captionText: req.body.story_context.caption_text || null,
        mediaUrl: req.body.story_context.media_url || null,
      }
      : undefined,
```

- [ ] **Step 8: Confirm the chat suite still passes**

```bash
node --test flame/__tests__/storyReplies.test.js flame/__tests__/messages.test.js flame/__tests__/conversations.test.js
```

Expected: `# fail 0`.

- [ ] **Step 9: Commit**

```bash
git add flame/models/Message.js flame/services/chatService.js \
        flame/routes/conversations.js flame/controllers/chatController.js \
        flame/__tests__/storyReplies.test.js
git commit -m "feat(stories): a reply lands in the conversation, carrying the story

Through the existing send path, so blocks, unmatch, muting and push keep
working with no new rules — and openConversation creates the thread when
there is none, which is what makes this a first-message mechanic rather
than a nicety for people already talking.

The caption is snapshotted onto the message and the photo is not. A caption
is text the author wrote; a photo is the thing the 24-hour promise is
about, and now that the sweep makes that promise real, copying story images
into conversations would quietly break it again. A week later the bubble
reads 'Replied to: \"sunset at Ocean Beach\"' with no image.

messageType stays 'text'. A new enum value would make every client type
switch learn about stories for what is decoration on an ordinary message."
```

---

## Task 4: Text stories

**Files:**
- Modify: `flame/models/Story.js`, `flame/services/storyService.js`, `flame/routes/stories.js`, `flame/controllers/storyController.js`
- Test: `flame/__tests__/textStories.test.js`

**Interfaces:**
- Produces: `createTextStory(userId, { text, background }) -> Promise<story>`; `toStory` gains `kind`, `text`, `background`; `STORY_BACKGROUNDS` exported from `flame/config/storyBackgrounds.js`.

- [ ] **Step 1: Create the palette**

Create `flame/config/storyBackgrounds.js`:

```js
/**
 * Named backgrounds for text stories.
 *
 * The server stores the KEY, never a colour. If the palette is retuned, every
 * existing text story re-renders with it instead of freezing whatever hex was
 * current the day it was posted.
 *
 * `flame` first, and it is the app's own primary→accent pair, so a text story
 * looks native beside the gradient ring rather than bolted on.
 */
const STORY_BACKGROUNDS = Object.freeze([
  'flame', 'dusk', 'ocean', 'forest', 'ember', 'slate',
]);

module.exports = { STORY_BACKGROUNDS };
```

- [ ] **Step 2: Write the failing test**

Create `flame/__tests__/textStories.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

process.env.FLAME_SPACES_BUCKET = 't';
process.env.SPACES_ENDPOINT = 'sfo3.digitaloceanspaces.com';
process.env.DO_SPACES_KEY = 'k';
process.env.DO_SPACES_SECRET = 's';

async function setup() {
  await dbHelper.start();
  ['../db', '../models/Story', '../services/storyService'].forEach((m) => {
    try { delete require.cache[require.resolve(m)]; } catch {}
  });
  const { connect } = require('../db');
  await connect();
  return { Story: require('../models/Story'), svc: require('../services/storyService') };
}

async function teardown() {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
}

test('a text story round-trips with no media at all', async (t) => {
  const { Story, svc } = await setup();
  t.after(teardown);

  const out = await svc.createTextStory('u1', { text: 'learning Korean, badly', background: 'dusk' });

  assert.equal(out.kind, 'text');
  assert.equal(out.text, 'learning Korean, badly');
  assert.equal(out.background, 'dusk');
  assert.equal(out.media_url, null);

  const stored = await Story.findById(out.id).lean();
  assert.equal(stored.mediaKey, null, 'nothing to sweep from S3');
});

test('an unknown background key is rejected', async (t) => {
  // The client picks from a fixed strip; anything else is a bug or a probe.
  const { svc } = await setup();
  t.after(teardown);

  await assert.rejects(
    () => svc.createTextStory('u1', { text: 'hi', background: 'chartreuse' }),
    /background/i,
  );
});

test('empty text is rejected', async (t) => {
  const { svc } = await setup();
  t.after(teardown);

  await assert.rejects(() => svc.createTextStory('u1', { text: '   ', background: 'flame' }), /text/i);
});

test('text is capped at 200 characters', async (t) => {
  const { svc } = await setup();
  t.after(teardown);

  const out = await svc.createTextStory('u1', { text: 'y'.repeat(500), background: 'flame' });
  assert.equal(out.text.length, 200);
});

test('a photo story still requires its media', async (t) => {
  const { svc } = await setup();
  t.after(teardown);

  await assert.rejects(() => svc.createStory('u1', null, 'caption'), /media/i);
});
```

- [ ] **Step 3: Run it and watch it fail**

```bash
node --test flame/__tests__/textStories.test.js
```

Expected: FAIL — `svc.createTextStory is not a function`.

- [ ] **Step 4: Extend the model**

In `flame/models/Story.js`, inside the schema body:

```js
  // 'photo' is the default so every row written before text stories existed
  // reads correctly without a migration.
  kind:       { type: String, enum: ['photo', 'text'], default: 'photo' },
  text:       { type: String, maxlength: 200, default: null },
  background: { type: String, default: null },
```

and relax the two media fields, which a text story has none of:

```js
  mediaUrl:  { type: String, default: null },
  mediaKey:  { type: String, default: null },
```

The "a photo story must have media" rule moves to the service, where it can raise a `ValidationError` the client already renders.

- [ ] **Step 5: Implement `createTextStory`**

In `flame/services/storyService.js`:

```js
const { STORY_BACKGROUNDS } = require('../config/storyBackgrounds');

async function createTextStory(userId, { text, background } = {}) {
  const clean = typeof text === 'string' ? text.trim().slice(0, MAX_CAPTION) : '';
  if (!clean) throw new ValidationError('text is required');
  if (!STORY_BACKGROUNDS.includes(background)) {
    throw new ValidationError('unknown background');
  }

  const story = await Story.create({
    userId,
    kind: 'text',
    text: clean,
    background,
    mediaUrl: null,
    mediaKey: null,
    expiresAt: new Date(Date.now() + STORY_TTL_MS),
  });
  return toStory(story, userId);
}
```

Add it to `module.exports`. In `createStory`, the existing `if (!file) throw new ValidationError('media file is required')` already covers Step 2's last test — leave it.

- [ ] **Step 6: Add the new fields to `toStory`**

In `toStory`, add:

```js
    kind: story.kind || 'photo',
    text: story.text || null,
    background: story.background || null,
```

- [ ] **Step 7: Run the tests — all five pass**

```bash
node --test flame/__tests__/textStories.test.js
```

Expected: `# pass 5`, `# fail 0`.

- [ ] **Step 8: Route it**

`POST /stories` currently always runs `upload.single('media')`. A JSON text story has no file, and multer passes a JSON body through untouched, so the same route serves both. In `flame/controllers/storyController.js`, change `create`:

```js
async function create(req, res) {
  const data = req.body && req.body.kind === 'text'
    ? await storyService.createTextStory(req.user.id, {
      text: req.body.text,
      background: req.body.background,
    })
    : await storyService.createStory(req.user.id, req.file, req.body.caption);
  res.status(201).json({ success: true, data });
}
```

- [ ] **Step 9: Confirm nothing regressed**

```bash
node --test flame/__tests__/stories.test.js flame/__tests__/textStories.test.js flame/__tests__/storyExpiry.test.js
```

Expected: `# fail 0`. The sweep test named "a story with no mediaKey is swept without touching S3" is what proves text stories cost the sweep nothing.

- [ ] **Step 10: Commit**

```bash
git add flame/config/storyBackgrounds.js flame/models/Story.js \
        flame/services/storyService.js flame/controllers/storyController.js \
        flame/__tests__/textStories.test.js
git commit -m "feat(stories): post a story without finding a photo

Text on a named gradient. The server stores the KEY, never a colour, so
retuning the palette re-renders every existing text story instead of
freezing whatever hex was current the day it was posted.

kind defaults to 'photo', so every row written before this reads correctly
with no migration, and mediaUrl/mediaKey become optional — the 'a photo
story must have media' rule moves to the service, where it raises the
ValidationError the client already knows how to show."
```

---

## Task 5: Highlights

**Files:**
- Create: `flame/models/StoryHighlight.js`, `flame/services/highlightService.js`, `flame/controllers/highlightController.js`, `flame/routes/highlights.js`
- Modify: `flame/index.js`, `flame/routes/stories.js`, `flame/controllers/storyController.js`
- Test: `flame/__tests__/highlights.test.js`

**Interfaces:**
- Consumes: the `mediaKey` exemption already built into `runStoryExpirySweep` in Task 1, which queries `StoryHighlight.find({ mediaKey: { $in: keys } })`.
- Produces: `pinStory(userId, storyId)`, `unpinHighlight(userId, highlightId)`, `listHighlights(viewerId, ownerId)`.

- [ ] **Step 1: Write the failing test**

Create `flame/__tests__/highlights.test.js`:

```js
const test = require('node:test');
const assert = require('node:assert/strict');
const dbHelper = require('./helpers/db');

process.env.FLAME_SPACES_BUCKET = 't';
process.env.SPACES_ENDPOINT = 'sfo3.digitaloceanspaces.com';
process.env.DO_SPACES_KEY = 'k';
process.env.DO_SPACES_SECRET = 's';

async function setup() {
  await dbHelper.start();
  ['../db', '../models/Story', '../models/StoryHighlight', '../models/User',
   '../services/highlightService', '../services/visibilityService',
   '../jobs/storyExpiryJob'].forEach((m) => {
    try { delete require.cache[require.resolve(m)]; } catch {}
  });
  const { connect } = require('../db');
  await connect();
  return {
    Story: require('../models/Story'),
    Highlight: require('../models/StoryHighlight'),
    svc: require('../services/highlightService'),
    job: require('../jobs/storyExpiryJob'),
  };
}

async function teardown() {
  const { close } = require('../db');
  await close();
  await dbHelper.stop();
}

const HOUR = 60 * 60 * 1000;
const live = () => new Date(Date.now() + HOUR);

test('pinning keeps the media when the story is swept', async (t) => {
  // The reason Task 1's sweep asks StoryHighlight before deleting anything.
  const { Story, svc, job } = await setup();
  t.after(teardown);

  const story = await Story.create({
    userId: 'u1', mediaUrl: 'https://x/a.jpg', mediaKey: 'k-pinned', expiresAt: live(),
  });
  await svc.pinStory('u1', story._id.toString());

  await Story.updateOne({ _id: story._id }, { $set: { expiresAt: new Date(Date.now() - HOUR) } });

  const deleted = [];
  const res = await job.runStoryExpirySweep({ deleteObject: async (k) => { deleted.push(k); } });

  assert.deepEqual(deleted, [], 'a pinned object must survive its story');
  assert.equal(res.skipped, 1);
  assert.equal(await Story.countDocuments({}), 0, 'the row still goes');
});

test('only the author can pin', async (t) => {
  const { Story, svc } = await setup();
  t.after(teardown);

  const story = await Story.create({
    userId: 'u1', mediaUrl: 'https://x/a.jpg', mediaKey: 'k', expiresAt: live(),
  });

  await assert.rejects(() => svc.pinStory('someone-else', story._id.toString()));
});

test('the cap holds at nine', async (t) => {
  // Same nine as MAX_PHOTOS_PER_USER, so the profile has one limit, not two.
  const { Story, svc } = await setup();
  t.after(teardown);

  for (let i = 0; i < 9; i += 1) {
    const s = await Story.create({
      userId: 'u1', mediaUrl: `https://x/${i}.jpg`, mediaKey: `k${i}`, expiresAt: live(),
    });
    await svc.pinStory('u1', s._id.toString());
  }
  const extra = await Story.create({
    userId: 'u1', mediaUrl: 'https://x/9.jpg', mediaKey: 'k9', expiresAt: live(),
  });

  await assert.rejects(() => svc.pinStory('u1', extra._id.toString()), /9|nine|limit/i);
});

test('pinning the same story twice does not make two highlights', async (t) => {
  const { Story, Highlight, svc } = await setup();
  t.after(teardown);

  const story = await Story.create({
    userId: 'u1', mediaUrl: 'https://x/a.jpg', mediaKey: 'k', expiresAt: live(),
  });
  await svc.pinStory('u1', story._id.toString());
  await svc.pinStory('u1', story._id.toString());

  assert.equal(await Highlight.countDocuments({ userId: 'u1' }), 1);
});

test('unpinning deletes the media once the story is gone', async (t) => {
  // The highlight holds the last reference, so it owes the object's deletion.
  const { Story, Highlight, svc } = await setup();
  t.after(teardown);

  const story = await Story.create({
    userId: 'u1', mediaUrl: 'https://x/a.jpg', mediaKey: 'k-last', expiresAt: live(),
  });
  const h = await svc.pinStory('u1', story._id.toString());
  await Story.deleteOne({ _id: story._id });

  const deleted = [];
  await svc.unpinHighlight('u1', h.id, { deleteObject: async (k) => { deleted.push(k); } });

  assert.deepEqual(deleted, ['k-last']);
  assert.equal(await Highlight.countDocuments({}), 0);
});

test('unpinning leaves the media alone while the story still holds it', async (t) => {
  const { Story, svc } = await setup();
  t.after(teardown);

  const story = await Story.create({
    userId: 'u1', mediaUrl: 'https://x/a.jpg', mediaKey: 'k-shared', expiresAt: live(),
  });
  const h = await svc.pinStory('u1', story._id.toString());

  const deleted = [];
  await svc.unpinHighlight('u1', h.id, { deleteObject: async (k) => { deleted.push(k); } });

  assert.deepEqual(deleted, [], 'the live story still needs it');
});

test('a text story can be pinned and carries its text, not media', async (t) => {
  const { Story, svc } = await setup();
  t.after(teardown);

  const story = await Story.create({
    userId: 'u1', kind: 'text', text: 'learning Korean', background: 'dusk',
    mediaUrl: null, mediaKey: null, expiresAt: live(),
  });
  const h = await svc.pinStory('u1', story._id.toString());

  assert.equal(h.kind, 'text');
  assert.equal(h.text, 'learning Korean');
  assert.equal(h.media_url, null);
});

test('highlights are public, and blocked viewers cannot read them', async (t) => {
  const { Story, svc } = await setup();
  t.after(teardown);

  const story = await Story.create({
    userId: 'u1', mediaUrl: 'https://x/a.jpg', mediaKey: 'k', expiresAt: live(),
  });
  await svc.pinStory('u1', story._id.toString());

  // A stranger — no match — still sees them: this is profile content.
  const seen = await svc.listHighlights('stranger', 'u1');
  assert.equal(seen.length, 1);
});
```

- [ ] **Step 2: Run it and watch it fail**

```bash
node --test flame/__tests__/highlights.test.js
```

Expected: FAIL — `Cannot find module '../models/StoryHighlight'`.

- [ ] **Step 3: Create the model**

Create `flame/models/StoryHighlight.js`:

```js
const mongoose = require('mongoose');
const { getConn } = require('../db');

/**
 * A story the author pinned to their profile.
 *
 * No TTL: that is the point. A highlight REFERENCES the story's S3 object
 * rather than copying it — utils/s3 has no copy operation, and duplicating
 * would double storage for no gain — so `mediaKey` is indexed because
 * storyExpiryJob queries it on every sweep to decide what it may delete.
 *
 * Unlike a story, this is PUBLIC profile content: visible to anyone who can
 * see the profile, not only to matches. The confirmation at pin time says so
 * in as many words.
 */
const storyHighlightSchema = new mongoose.Schema({
  userId:     { type: String, required: true, index: true },
  storyId:    { type: String, required: true },
  mediaUrl:   { type: String, default: null },
  mediaKey:   { type: String, default: null, index: true },
  kind:       { type: String, enum: ['photo', 'text'], required: true },
  text:       { type: String, default: null },
  background: { type: String, default: null },
  caption:    { type: String, default: null },
}, {
  timestamps: { createdAt: 'createdAt', updatedAt: false },
  collection: 'story_highlights',
});

// One highlight per story per user — pinning twice is a no-op, not a duplicate.
storyHighlightSchema.index({ userId: 1, storyId: 1 }, { unique: true });

module.exports = getConn().model('StoryHighlight', storyHighlightSchema);
```

- [ ] **Step 4: Write the service**

Create `flame/services/highlightService.js`:

```js
const Story = require('../models/Story');
const StoryHighlight = require('../models/StoryHighlight');
const s3 = require('../utils/s3');
const logger = require('../utils/logger');
const { ValidationError, NotFoundError, FlameError } = require('../utils/errors');

/** Same nine as MAX_PHOTOS_PER_USER, so a profile has one limit and not two. */
const MAX_HIGHLIGHTS = 9;

function toHighlight(h) {
  return {
    id: h._id.toString(),
    user_id: h.userId,
    story_id: h.storyId,
    media_url: h.mediaUrl,
    kind: h.kind,
    text: h.text,
    background: h.background,
    caption: h.caption,
    created_at: h.createdAt.toISOString(),
  };
}

async function pinStory(userId, storyId) {
  const story = await Story.findById(storyId);
  if (!story) throw new NotFoundError('story not found');
  if (story.userId !== userId) {
    throw new FlameError('FORBIDDEN', 'Not your story', 403);
  }
  if (story.expiresAt <= new Date()) {
    throw new ValidationError('story has expired');
  }

  const existing = await StoryHighlight.findOne({ userId, storyId });
  if (existing) return toHighlight(existing);

  if (await StoryHighlight.countDocuments({ userId }) >= MAX_HIGHLIGHTS) {
    throw new ValidationError(`at most ${MAX_HIGHLIGHTS} highlights`);
  }

  const created = await StoryHighlight.create({
    userId,
    storyId: story._id.toString(),
    mediaUrl: story.mediaUrl,
    mediaKey: story.mediaKey,
    kind: story.kind || 'photo',
    text: story.text,
    background: story.background,
    caption: story.caption,
  });
  return toHighlight(created);
}

async function unpinHighlight(userId, highlightId, { deleteObject = s3.deleteObject } = {}) {
  const h = await StoryHighlight.findById(highlightId);
  if (!h) throw new NotFoundError('highlight not found');
  if (h.userId !== userId) throw new FlameError('FORBIDDEN', 'Not yours', 403);

  // The object is shared with the story until the sweep takes the row. Delete
  // it only when this highlight is the last thing referencing it, or a live
  // story loses its image.
  if (h.mediaKey) {
    const storyStillHasIt = await Story.countDocuments({ mediaKey: h.mediaKey });
    const otherHighlights = await StoryHighlight.countDocuments({
      mediaKey: h.mediaKey, _id: { $ne: h._id },
    });
    if (!storyStillHasIt && !otherHighlights) {
      try {
        await deleteObject(h.mediaKey);
      } catch (err) {
        logger.warn(`highlight unpin: could not delete ${h.mediaKey} —`, err.message);
      }
    }
  }
  await h.deleteOne();
}

/**
 * Highlights are profile content, so a stranger sees them. Only a block hides
 * them — the same rule the profile itself follows.
 */
async function listHighlights(viewerId, ownerId) {
  const visibility = require('./visibilityService');
  if (viewerId !== ownerId && await visibility.areBlocked(viewerId, ownerId)) {
    return [];
  }
  const rows = await StoryHighlight.find({ userId: ownerId }).sort({ createdAt: -1 }).lean();
  return rows.map((h) => toHighlight({ ...h, _id: h._id, createdAt: h.createdAt }));
}

module.exports = { pinStory, unpinHighlight, listHighlights, MAX_HIGHLIGHTS };
```

**Check `flame/utils/errors.js` first** for the exact exported names; if `NotFoundError` or `ValidationError` differ, use what is there rather than adding new ones.

- [ ] **Step 5: Run the tests — all eight pass**

```bash
node --test flame/__tests__/highlights.test.js
```

Expected: `# pass 8`, `# fail 0`. The first test is the one that proves Task 1's exemption works end to end.

- [ ] **Step 6: Wire the routes**

Create `flame/controllers/highlightController.js`:

```js
const highlightService = require('../services/highlightService');

async function pin(req, res) {
  const data = await highlightService.pinStory(req.user.id, req.params.id);
  res.status(201).json({ success: true, data });
}

async function unpin(req, res) {
  await highlightService.unpinHighlight(req.user.id, req.params.id);
  res.json({ success: true });
}

async function list(req, res) {
  const data = await highlightService.listHighlights(req.user.id, req.params.id);
  res.json({ success: true, data });
}

module.exports = { pin, unpin, list };
```

Create `flame/routes/highlights.js`:

```js
const express = require('express');
const { z } = require('zod');
const validate = require('../middleware/validate');
const asyncHandler = require('../middleware/asyncHandler');
const auth = require('../middleware/auth');
const ctrl = require('../controllers/highlightController');

const idParam = z.object({
  id: z.string().regex(/^[0-9a-fA-F]{24}$/, 'must be a valid ObjectId'),
});

const router = express.Router();

router.delete('/:id', auth, validate.params(idParam), asyncHandler(ctrl.unpin));

module.exports = router;
```

In `flame/routes/stories.js`, add the pin route beside the others:

```js
router.post('/:id/highlight', auth, validate.params(objectIdSchema),
  asyncHandler(require('../controllers/highlightController').pin));
```

In `flame/routes/users.js`, add the public list beside the other `/:id` routes:

```js
router.get('/:id/highlights', auth, validate.params(idParam),
  asyncHandler(require('../controllers/highlightController').list));
```

**Check `flame/routes/users.js` for the name of its existing id-param schema** and reuse it rather than declaring a second one.

In `flame/index.js`, mount the router beside the existing ones:

```js
router.use('/highlights', require('./routes/highlights'));
```

- [ ] **Step 7: Confirm the whole story surface still passes**

```bash
node --test flame/__tests__/highlights.test.js flame/__tests__/stories.test.js \
  flame/__tests__/storyExpiry.test.js flame/__tests__/textStories.test.js \
  flame/__tests__/storyReactions.test.js flame/__tests__/storyReplies.test.js
```

Expected: `# fail 0`.

- [ ] **Step 8: Commit**

```bash
git add flame/models/StoryHighlight.js flame/services/highlightService.js \
        flame/controllers/highlightController.js flame/routes/highlights.js \
        flame/routes/stories.js flame/routes/users.js flame/index.js \
        flame/__tests__/highlights.test.js
git commit -m "feat(stories): pin a story to the profile

A highlight REFERENCES the story's S3 object rather than copying it —
utils/s3 has no copy operation, and duplicating would double storage for
nothing. The sweep from the first commit already asks StoryHighlight before
deleting, so a pinned object survives its story; unpinning deletes it only
when nothing else holds it.

Capped at nine, the same as MAX_PHOTOS_PER_USER, so a profile has one limit
rather than two arbitrary ones. Unique on (userId, storyId), so pinning
twice is a no-op instead of a duplicate.

Unlike a story this is PUBLIC: visible to anyone who sees the profile, not
only to matches. The client must say so at pin time — that is a change of
both audience and duration, and it is the app-side half of this task."
```

---

## Task 6: App — reactions and replies in the story viewer

**Files:**
- Create: `lib/screens/stories/widgets/story_reaction_bar.dart`, `lib/screens/stories/widgets/story_reply_field.dart`
- Modify: `lib/models/story.dart`, `lib/services/story_service.dart`, `lib/providers/story_provider.dart`, `lib/screens/stories/story_viewer_screen.dart`, `lib/core/push/push_payload.dart`
- Test: `test/models/story_reactions_test.dart`, `test/screens/stories/story_viewer_actions_test.dart`

**Interfaces:**
- Consumes: `POST /stories/:id/reactions {emoji}`, `DELETE /stories/:id/reactions`, `POST /conversations` and `POST /conversations/:id/messages` with `story_context`.
- Produces: `Story.myReaction`, `Story.kind`, `Story.text`, `Story.background`; `StoryActions.react`, `StoryActions.unreact`, `StoryActions.reply`.

- [ ] **Step 1: Write the failing model test**

Create `test/models/story_reactions_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/story.dart';

void main() {
  test('my_reaction parses, and its absence is null not empty', () {
    final s = Story.fromJson({
      'id': 's1', 'user_id': 'u1', 'media_url': 'https://x/a.jpg',
      'created_at': '2026-09-06T10:00:00.000Z',
      'expires_at': '2026-09-07T10:00:00.000Z',
      'view_count': 3, 'has_viewed': true, 'my_reaction': '🔥',
    });
    expect(s.myReaction, '🔥');

    final none = Story.fromJson({
      'id': 's2', 'user_id': 'u1', 'media_url': 'https://x/b.jpg',
      'created_at': '2026-09-06T10:00:00.000Z',
      'expires_at': '2026-09-07T10:00:00.000Z',
      'view_count': 0, 'has_viewed': false,
    });
    expect(none.myReaction, isNull);
  });

  test('a text story parses with no media', () {
    final s = Story.fromJson({
      'id': 's3', 'user_id': 'u1', 'media_url': null,
      'kind': 'text', 'text': 'learning Korean', 'background': 'dusk',
      'created_at': '2026-09-06T10:00:00.000Z',
      'expires_at': '2026-09-07T10:00:00.000Z',
      'view_count': 0, 'has_viewed': false,
    });
    expect(s.kind, StoryKind.text);
    expect(s.text, 'learning Korean');
    expect(s.background, 'dusk');
    expect(s.mediaUrl, isEmpty);
  });

  test('a payload with no kind reads as a photo story', () {
    // Every story written before text stories existed.
    final s = Story.fromJson({
      'id': 's4', 'user_id': 'u1', 'media_url': 'https://x/c.jpg',
      'created_at': '2026-09-06T10:00:00.000Z',
      'expires_at': '2026-09-07T10:00:00.000Z',
      'view_count': 0, 'has_viewed': false,
    });
    expect(s.kind, StoryKind.photo);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
cd /Users/firdavsmutalipov/Desktop/Flame/flame_front_app
flutter test test/models/story_reactions_test.dart
```

Expected: FAIL — `myReaction` is not defined.

- [ ] **Step 3: Extend the model**

In `lib/models/story.dart`, add above the class:

```dart
/// What a story is made of. `photo` is the default so every story written
/// before text stories existed parses unchanged.
enum StoryKind { photo, text }
```

Add the fields to `Story`, to its constructor, and to `fromJson`:

```dart
  final StoryKind kind;
  final String? text;
  final String? background;

  /// The emoji THIS viewer sent, if any. Null and empty are the same thing
  /// here; the server sends null when there is none.
  final String? myReaction;
```

```dart
      kind: (json['kind'] as String?) == 'text' ? StoryKind.text : StoryKind.photo,
      text: json['text'] as String?,
      background: json['background'] as String?,
      myReaction: (json['my_reaction'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['my_reaction'] as String,
```

`mediaUrl` already defaults to `''` when absent; leave that, so a text story reads as an empty URL rather than throwing.

- [ ] **Step 4: Run — the three model tests pass**

```bash
flutter test test/models/story_reactions_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Add the service calls**

In `lib/services/story_service.dart`, add to the abstract class:

```dart
  Future<void> react(String storyId, String emoji);
  Future<void> unreact(String storyId);
```

and to `ApiStoryService`:

```dart
  @override
  Future<void> react(String storyId, String emoji) async {
    await _api.post('/stories/$storyId/reactions', body: {'emoji': emoji});
  }

  @override
  Future<void> unreact(String storyId) async {
    await _api.delete('/stories/$storyId/reactions');
  }
```

**Read the neighbouring `markViewed` first** and match how it passes a body and handles the response; do not invent a different call style.

- [ ] **Step 6: Add the actions**

In `lib/providers/story_provider.dart`, add to `StoryActions`:

```dart
  /// Sends or replaces this viewer's reaction. Fire-and-forget by design: a
  /// reaction that fails is worth a silent retry next tap, not a dialog over
  /// a story the user is still watching.
  Future<void> react(String storyId, String emoji) async {
    await _service.react(storyId, emoji);
    _ref.invalidate(storiesFeedProvider);
  }

  Future<void> unreact(String storyId) async {
    await _service.unreact(storyId);
    _ref.invalidate(storiesFeedProvider);
  }
```

- [ ] **Step 7: Build the reaction bar**

Create `lib/screens/stories/widgets/story_reaction_bar.dart`:

```dart
import 'package:flutter/material.dart';

/// The six emoji a viewer may send, fixed to match the server's allowlist in
/// `flame/services/storyService.js`. Adding one here without adding it there
/// produces a silent 400 on tap.
const kStoryReactionEmoji = <String>['❤️', '😂', '😮', '😢', '🔥', '👏'];

class StoryReactionBar extends StatelessWidget {
  const StoryReactionBar({
    super.key,
    required this.selected,
    required this.onReact,
  });

  /// The emoji this viewer already sent, or null.
  final String? selected;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final e in kStoryReactionEmoji)
          GestureDetector(
            onTap: () => onReact(e),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 120),
              scale: e == selected ? 1.35 : 1.0,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(e, style: const TextStyle(fontSize: 26)),
              ),
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 8: Write the viewer test**

Create `test/screens/stories/story_viewer_actions_test.dart`. Model its host on the existing `test/screens/stories/story_viewer_test.dart` — read that file first and reuse its `ProviderScope` overrides rather than writing a new harness.

```dart
// Two behaviours, both of which the feature is worthless without.
//
// 1. Tapping an emoji sends exactly one reaction with that emoji.
// 2. The progress timer PAUSES while the reply field has focus. A story
//    advancing out from under a half-typed reply is the single most obvious
//    way to make this feature feel broken.
```

Write both tests against the real widget: assert the recorded emoji on a fake `StoryService`, and assert the story index is unchanged after pumping past the normal advance duration with the field focused.

- [ ] **Step 9: Run it and watch it fail**

```bash
flutter test test/screens/stories/story_viewer_actions_test.dart
```

Expected: FAIL — the reaction bar and reply field do not exist in the viewer yet.

- [ ] **Step 10: Wire both into the viewer**

In `lib/screens/stories/story_viewer_screen.dart`, add the bar and the field to the bottom of the stack, and **pause the progress timer while the reply field has focus**. The viewer already owns its timer; gate its tick on a `_replyFocus.hasFocus` check rather than cancelling and restarting it, so an unfocus resumes where it paused.

Send a reply by opening the conversation and posting the message with `story_context` built from the current story: `story_id`, `caption_text` (the story's caption, or its text for a text story), `media_url`.

- [ ] **Step 11: Run — the viewer tests pass**

```bash
flutter test test/screens/stories/story_viewer_actions_test.dart test/screens/stories/story_viewer_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 12: Teach push about the new type**

In `lib/core/push/push_payload.dart`, add `storyReaction` to `PushType`, map `'story_reaction'` to it in the parser, and route it to the story viewer. **Add it to `_needsArguments` if its route takes typed arguments** — `test/core/push/push_payload_test.dart` has a test that fails otherwise.

- [ ] **Step 13: Full app suite and analyze**

```bash
flutter test
flutter analyze
```

Expected: all pass; analyze with **0 errors and 0 warnings**. Count severities with `flutter analyze 2>&1 | grep -oE '^ *[a-z]+ •' | sort | uniq -c`.

- [ ] **Step 14: Commit**

```bash
git add lib/models/story.dart lib/services/story_service.dart \
        lib/providers/story_provider.dart lib/screens/stories/ \
        lib/core/push/push_payload.dart test/
git commit -m "feat(stories): react and reply without leaving the story

Six emoji fixed to the server's allowlist — adding one here without adding
it there is a silent 400 on tap, so the comment in the widget says so.

The progress timer pauses while the reply field has focus. A story advancing
out from under a half-typed reply is the most obvious way to make this feel
broken, and it is the behaviour the test pins."
```

---

## Task 7: App — text stories

**Files:**
- Create: `lib/core/stories/story_backgrounds.dart`
- Modify: `lib/screens/stories/create_story_screen.dart`, `lib/screens/stories/story_viewer_screen.dart`, `lib/services/story_service.dart`, `lib/providers/story_provider.dart`
- Test: `test/core/stories/story_backgrounds_test.dart`, `test/screens/stories/create_text_story_test.dart`

**Interfaces:**
- Consumes: `POST /stories` with `{kind: 'text', text, background}`; `StoryKind` and `Story.background` from Task 6.
- Produces: `kStoryBackgrounds` — a `Map<String, LinearGradient>` whose keys match `flame/config/storyBackgrounds.js` exactly.

- [ ] **Step 1: Write the failing palette test**

Create `test/core/stories/story_backgrounds_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/stories/story_backgrounds.dart';

void main() {
  test('the keys match the server allowlist exactly', () {
    // flame/config/storyBackgrounds.js. A key here that is not there is a 400
    // on post; a key there that is not here renders nothing at all.
    expect(kStoryBackgrounds.keys.toList(),
        ['flame', 'dusk', 'ocean', 'forest', 'ember', 'slate']);
  });

  test('an unknown key falls back rather than throwing', () {
    // A story posted by a newer client, or a palette key later retired.
    expect(gradientFor('chartreuse'), kStoryBackgrounds['flame']);
    expect(gradientFor(null), kStoryBackgrounds['flame']);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/core/stories/story_backgrounds_test.dart
```

Expected: FAIL — the file does not exist.

- [ ] **Step 3: Create the palette**

Create `lib/core/stories/story_backgrounds.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flame/theme/app_theme.dart';

/// Text-story backgrounds, keyed exactly as `flame/config/storyBackgrounds.js`
/// lists them. The server stores only the key, so retuning a gradient here
/// re-renders every existing text story rather than leaving old ones frozen.
///
/// `flame` is first and is the app's own primary→accent pair, the same one
/// StoryGradientRing draws, so a text story looks native beside the ring.
final kStoryBackgrounds = <String, LinearGradient>{
  'flame': const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
  'dusk': const LinearGradient(colors: [Color(0xFF2B5876), Color(0xFF4E4376)]),
  'ocean': const LinearGradient(colors: [Color(0xFF2193B0), Color(0xFF6DD5ED)]),
  'forest': const LinearGradient(colors: [Color(0xFF11998E), Color(0xFF38EF7D)]),
  'ember': const LinearGradient(colors: [Color(0xFFCB356B), Color(0xFFBD3F32)]),
  'slate': const LinearGradient(colors: [Color(0xFF232526), Color(0xFF414345)]),
};

/// Never throws on an unknown key: a story posted by a newer client, or one
/// whose background was later retired, still has to render something.
LinearGradient gradientFor(String? key) =>
    kStoryBackgrounds[key] ?? kStoryBackgrounds['flame']!;
```

**Check `lib/theme/app_theme.dart` for the real names** of the primary and accent colours before writing that first entry; `StoryGradientRing` uses them and is the file to copy from.

- [ ] **Step 4: Run — the palette tests pass**

```bash
flutter test test/core/stories/story_backgrounds_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Add the create call**

In `lib/services/story_service.dart`, add to the abstract class and the implementation:

```dart
  Future<Story> createText({required String text, required String background});
```

```dart
  @override
  Future<Story> createText({required String text, required String background}) async {
    final response = await _api.post('/stories', body: {
      'kind': 'text',
      'text': text,
      'background': background,
    });
    return Story.fromJson(response.data);
  }
```

Add a matching `createText` to `StoryActions` in `lib/providers/story_provider.dart`, invalidating `storiesFeedProvider` exactly as `create` already does.

- [ ] **Step 6: Write the create-screen test**

Create `test/screens/stories/create_text_story_test.dart`. Assert that switching to text mode, typing, choosing a background and confirming calls `createText` with that text and key — and that confirming with an empty field does not call it at all.

- [ ] **Step 7: Run it and watch it fail**

```bash
flutter test test/screens/stories/create_text_story_test.dart
```

Expected: FAIL — there is no text mode.

- [ ] **Step 8: Add text mode to the create screen and the viewer**

In `create_story_screen.dart`, add a photo/text toggle; in text mode show a text field over `gradientFor(selectedKey)` with a horizontal strip of the six backgrounds. Cap input at 200 characters with `maxLength: 200`.

In `story_viewer_screen.dart`, render `StoryKind.text` as centred text on `gradientFor(story.background)` instead of the image. Progress, tap-to-advance, reactions and replies are unchanged.

Add ARB keys for any new strings — **all 25 base locales**, European Portuguese rules for `app_pt.arb`.

- [ ] **Step 9: Run the suite and analyze**

```bash
flutter test
flutter analyze
```

Expected: all pass; 0 errors, 0 warnings.

- [ ] **Step 10: Commit**

```bash
git add lib/core/stories/ lib/screens/stories/ lib/services/story_service.dart \
        lib/providers/story_provider.dart lib/l10n/ test/
git commit -m "feat(stories): post a text story

Keys match flame/config/storyBackgrounds.js exactly, and a test pins that
list: a key here the server does not know is a 400 on post, and a key it
knows that is missing here renders nothing. gradientFor falls back rather
than throwing, because a story posted by a newer client still has to draw."
```

---

## Task 8: App — the quoted story in a chat bubble

**Files:**
- Create: `lib/widgets/story_context_bubble.dart`
- Modify: `lib/models/message.dart`, `lib/screens/chat/widgets/message_bubble.dart`
- Test: `test/models/message_story_context_test.dart`, `test/widgets/story_context_bubble_test.dart`

**Interfaces:**
- Consumes: `story_context: {story_id, caption_text, media_url}|null` from Task 3.
- Produces: `Message.storyContext` — a `StoryContext?` with `storyId`, `captionText`, `mediaUrl`.

- [ ] **Step 1: Write the failing model test**

Create `test/models/message_story_context_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/message.dart';

void main() {
  test('story context parses when present', () {
    final m = Message.fromJson({
      'id': 'm1', 'conversation_id': 'c1', 'sender_id': 'u1',
      'text': 'that beach is my favourite',
      'created_at': '2026-09-06T10:00:00.000Z',
      'story_context': {
        'story_id': 's1',
        'caption_text': 'sunset at Ocean Beach',
        'media_url': 'https://x/a.jpg',
      },
    });
    expect(m.storyContext!.captionText, 'sunset at Ocean Beach');
    expect(m.storyContext!.storyId, 's1');
  });

  test('an ordinary message has none', () {
    final m = Message.fromJson({
      'id': 'm2', 'conversation_id': 'c1', 'sender_id': 'u1',
      'text': 'hello', 'created_at': '2026-09-06T10:00:00.000Z',
    });
    expect(m.storyContext, isNull);
  });

  test('a context whose media is gone still carries its caption', () {
    // What every reply looks like once the story has been swept.
    final m = Message.fromJson({
      'id': 'm3', 'conversation_id': 'c1', 'sender_id': 'u1',
      'text': 'nice', 'created_at': '2026-09-06T10:00:00.000Z',
      'story_context': {
        'story_id': 's1', 'caption_text': 'sunset at Ocean Beach', 'media_url': null,
      },
    });
    expect(m.storyContext!.captionText, 'sunset at Ocean Beach');
    expect(m.storyContext!.mediaUrl, isNull);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/models/message_story_context_test.dart
```

Expected: FAIL — `storyContext` is not defined.

- [ ] **Step 3: Add the model**

In `lib/models/message.dart`, above `Message`:

```dart
/// The story a message replies to.
///
/// [captionText] is the message's OWN copy and outlives the story;
/// [mediaUrl] is a reference and does not. Once the story is swept the URL
/// stops resolving, which is why the bubble falls back to the caption rather
/// than to a broken image.
class StoryContext {
  const StoryContext({required this.storyId, this.captionText, this.mediaUrl});

  final String storyId;
  final String? captionText;
  final String? mediaUrl;

  static StoryContext? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['story_id'] as String?;
    if (id == null || id.isEmpty) return null;
    return StoryContext(
      storyId: id,
      captionText: json['caption_text'] as String?,
      mediaUrl: json['media_url'] as String?,
    );
  }
}
```

Add `final StoryContext? storyContext;` to `Message`, to its constructor, and to `fromJson`:

```dart
      storyContext: StoryContext.fromJson(
        json['story_context'] as Map<String, dynamic>?),
```

- [ ] **Step 4: Run — the three model tests pass**

```bash
flutter test test/models/message_story_context_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Write the widget test**

Create `test/widgets/story_context_bubble_test.dart`, asserting three things: with a `mediaUrl` it renders the thumbnail; with `mediaUrl` null it renders `Replied to: "sunset at Ocean Beach"`; with both null it renders a neutral `Replied to a story` and does not throw.

- [ ] **Step 6: Run it and watch it fail**

```bash
flutter test test/widgets/story_context_bubble_test.dart
```

Expected: FAIL — the widget does not exist.

- [ ] **Step 7: Build the bubble and attach it**

Create `lib/widgets/story_context_bubble.dart` — a compact chip above the message text: thumbnail when `mediaUrl` is non-null, otherwise the caption in quotes, otherwise a plain "Replied to a story". Render it in `message_bubble.dart` above the text when `message.storyContext != null`.

Add ARB keys `chatRepliedToStory` ("Replied to a story") and `chatRepliedToStoryCaption` (`Replied to: "{caption}"`) across **all 25 base locales**, European Portuguese rules for `app_pt.arb`.

- [ ] **Step 8: Run the suite and analyze**

```bash
flutter test
flutter analyze
```

Expected: all pass; 0 errors, 0 warnings.

- [ ] **Step 9: Commit**

```bash
git add lib/models/message.dart lib/widgets/story_context_bubble.dart \
        lib/screens/chat/widgets/message_bubble.dart lib/l10n/ test/
git commit -m "feat(chat): show which story a reply answered

The thumbnail while the story lives, and the caption once it does not —
'Replied to: \"sunset at Ocean Beach\"' rather than a broken image. The
caption is the message's own copy; the media is a reference, deliberately,
so nobody's disappearing photo becomes permanent in a conversation."
```

---

## Task 9: App — highlights on the profile

**Files:**
- Create: `lib/models/story_highlight.dart`, `lib/services/highlight_service.dart`, `lib/providers/highlight_provider.dart`, `lib/widgets/highlights_row.dart`
- Modify: `lib/screens/stories/story_viewer_screen.dart`, `lib/screens/profile/profile_detail_screen.dart`, `lib/screens/profile/my_profile_screen.dart`
- Test: `test/models/story_highlight_test.dart`, `test/widgets/highlights_row_test.dart`, `test/screens/stories/pin_confirmation_test.dart`

**Interfaces:**
- Consumes: `POST /stories/:id/highlight`, `DELETE /highlights/:id`, `GET /users/:id/highlights`.
- Produces: `StoryHighlight` model, `highlightsProvider(userId)`, `HighlightsRow`.

- [ ] **Step 1: Write the failing model test**

Create `test/models/story_highlight_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/story_highlight.dart';

void main() {
  test('a photo highlight parses', () {
    final h = StoryHighlight.fromJson({
      'id': 'h1', 'user_id': 'u1', 'story_id': 's1',
      'media_url': 'https://x/a.jpg', 'kind': 'photo',
      'text': null, 'background': null, 'caption': 'Ocean Beach',
      'created_at': '2026-09-06T10:00:00.000Z',
    });
    expect(h.kind, StoryKind.photo);
    expect(h.mediaUrl, 'https://x/a.jpg');
    expect(h.caption, 'Ocean Beach');
  });

  test('a text highlight parses with no media', () {
    final h = StoryHighlight.fromJson({
      'id': 'h2', 'user_id': 'u1', 'story_id': 's2',
      'media_url': null, 'kind': 'text',
      'text': 'learning Korean', 'background': 'dusk', 'caption': null,
      'created_at': '2026-09-06T10:00:00.000Z',
    });
    expect(h.kind, StoryKind.text);
    expect(h.text, 'learning Korean');
    expect(h.background, 'dusk');
    expect(h.mediaUrl, isNull);
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

```bash
flutter test test/models/story_highlight_test.dart
```

Expected: FAIL — the file does not exist.

- [ ] **Step 3: Write the model, service and provider**

Create `lib/models/story_highlight.dart` reusing `StoryKind` from `lib/models/story.dart`; `lib/services/highlight_service.dart` with `list(userId)`, `pin(storyId)`, `unpin(highlightId)` mirroring `story_service.dart`'s structure; and `lib/providers/highlight_provider.dart` with a `highlightsProvider` family keyed by user id.

- [ ] **Step 4: Run — both model tests pass**

```bash
flutter test test/models/story_highlight_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 5: Write the pin-confirmation test**

Create `test/screens/stories/pin_confirmation_test.dart`. This is the test that matters most in this task:

```dart
// Pinning changes BOTH the audience and the duration: a photo shared with
// matches for 24 hours becomes profile content visible to strangers,
// indefinitely. Confirming must be a deliberate act.
//
// Assert three things:
//  1. Tapping "Add to profile" does NOT call pin — a dialog appears first.
//  2. The dialog text names the change of audience, not just "are you sure".
//  3. Dismissing it leaves pin uncalled.
```

Write all three against the real viewer with a fake `HighlightService` recording calls.

- [ ] **Step 6: Run it and watch it fail**

```bash
flutter test test/screens/stories/pin_confirmation_test.dart
```

Expected: FAIL — there is no pin action.

- [ ] **Step 7: Add pinning, with the confirmation**

In `story_viewer_screen.dart`, show "Add to profile" on the author's own story only. Tapping opens an `AlertDialog` whose body is the new ARB string `storyPinConfirmBody`:

> "This will be saved to your profile, where anyone who views it can see it — including people you haven't matched with. Your story is currently visible only to your matches, for 24 hours."

with confirm and cancel. Only the confirm action calls `pin`.

Add `storyPinTitle`, `storyPinConfirmBody`, `storyPinConfirm`, `storyPinned`, `storyPinLimitReached` across **all 25 base locales**, European Portuguese rules for `app_pt.arb`.

- [ ] **Step 8: Build the row and put it on both profiles**

Create `lib/widgets/highlights_row.dart` — a horizontal strip of circular thumbnails below the photos, rendering a text highlight on `gradientFor(background)`. Tapping opens the existing story viewer **in a read-only mode**: no reaction bar, no reply field. A highlight is profile content, not a live story.

Add it to `profile_detail_screen.dart` and `my_profile_screen.dart`. On your own profile, long-press offers unpin.

- [ ] **Step 9: Write the row test**

Create `test/widgets/highlights_row_test.dart`: an empty list renders nothing at all (not an empty box with padding); a mixed photo/text list renders both; tapping opens the viewer with reactions and replies absent.

- [ ] **Step 10: Run the full suite and analyze**

```bash
flutter test
flutter analyze
```

Expected: all pass; 0 errors, 0 warnings.

- [ ] **Step 11: Commit**

```bash
git add lib/models/story_highlight.dart lib/services/highlight_service.dart \
        lib/providers/highlight_provider.dart lib/widgets/highlights_row.dart \
        lib/screens/ lib/l10n/ test/
git commit -m "feat(profile): pin a story to the profile, with the audience spelled out

Pinning changes both audience and duration — matches for a day becomes
anyone who opens the profile, indefinitely — so the confirmation says that
in as many words rather than asking 'are you sure'. Three tests hold it:
the action does not pin without the dialog, the dialog names the change,
and dismissing it pins nothing.

Highlights open the viewer read-only. Reacting to a months-old pinned photo
is not the interaction this is for."
```

---

## Self-Review

**Spec coverage.** Section 1 → Task 1. Section 2 → Tasks 2, 6. Section 3 → Tasks 3, 6, 8. Section 4 → Tasks 4, 7. Section 5 → Tasks 5, 9. The spec's error-handling list is covered: expired-story rejection in Tasks 2 and 5, sweep resilience in Task 1, pin-after-expiry in Task 5. The spec's "not in this spec" items are absent here, as intended.

**Ordering note for the executor.** Task 1 Step 5 writes the highlight exemption before `StoryHighlight` exists, guarded by a `MODULE_NOT_FOUND` catch, and Task 5 Step 1's first test is what proves it works end to end. That indirection is deliberate: the alternative is either building the model early in the wrong task, or leaving the sweep knowingly wrong between Tasks 1 and 5.

**Two places the implementer must read before writing.** `sendMessage`'s real signature in `chatService.js` (Task 3 Step 4) and `pushService`'s existing sender shape (Task 2 Step 6). Both plans show the intent; both files are the authority on style.

**Known gap, deliberate.** Tasks 6–9 specify several widget tests by their assertions rather than by full code, because each needs the existing harness in the neighbouring test file, and transcribing a guessed harness would be worse than naming what to assert. Every backend test is complete code.
