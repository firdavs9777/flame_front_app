# Stories that start conversations — design

**Date:** 2026-09-05
**Status:** approved in brainstorming, not yet planned

## The problem

Flame's stories are a broadcast into the void. You post a photo, it expires in
24 hours, and a counter tells you how many people looked. The viewer's only
interaction is tapping to advance. There is no way to respond to a story at
all.

That is the wrong shape for a dating app. Stories exist in Hinge, Bumble and
Instagram because they lower the barrier to a first message: replying to
something specific converts far better than a cold opener into an empty box.

The feed is already matches-only — `storyService.visibleAuthorFilter` filters
authors to `matchService.matchedIdsFor`, and `canView` requires `areMatched`.
So stories are not a discovery surface and never were. That makes the problem
they should solve precise: **matches who never exchanged a first message.**

A second problem feeds the first. There is nothing to look at. Posting takes a
photo, and the result vanishes in a day, so the effort buys nothing lasting.

## What we are building

1. Take control of story media lifetime (prerequisite — see below).
2. Emoji reactions on a story.
3. Replies that land in the existing conversation, carrying story context.
4. Text stories, so posting does not require finding a photo.
5. Highlights, so a story can become lasting profile content.

Sections 2 and 3 serve "start conversations". Sections 4 and 5 serve "give
people a reason to post". Section 1 is not optional and is explained next.

---

## 1. Media lifetime — the prerequisite

### Stories do not currently disappear

`storyService.createStory` uploads with `ACL: 'public-read'` (`utils/s3.js:52`),
producing a permanently public URL. Expiry is a MongoDB TTL index on
`expiresAt` (`models/Story.js`). **TTL deletion removes the document and runs no
application code**, so `s3.deleteObject` never fires on expiry — it fires only
in `deleteStory`, when an author deletes by hand.

The document carries `mediaKey`. When TTL removes the document, the key goes
with it, so the object is not merely undeleted — it is unreferenced. Nothing in
the system can name it again without listing the bucket.

Every story photo ever posted to Flame is therefore still publicly fetchable at
its original URL. "Disappears in 24 hours" describes the UI, not the data.

This is a privacy defect on its own terms. It is also load-bearing for this
work: highlights require media to outlive the story deliberately, which is
impossible while expiry is an uncontrolled side effect of a TTL index.

### The fix

Add a sweep job, `flame/jobs/storyExpiryJob.js`, registered on the existing
`pushScheduler` tick:

1. Find stories where `expiresAt < now`.
2. Skip any whose `mediaKey` is referenced by a `StoryHighlight` (section 5).
3. Delete the S3 object, then delete the row.
4. Log counts swept, skipped and failed.

Deleting the object **before** the row is deliberate. If the process dies
between the two, the row survives with a dead `mediaKey`, and the next sweep
retries — a visible broken image for one tick. The other order loses the key
forever and recreates exactly the leak this removes.

Keep the TTL index as a backstop, with `expireAfterSeconds` raised so the sweep
always runs first. The index guarantees rows never accumulate unboundedly if
the job is down; the job guarantees objects are deleted. **Raise the TTL to 7
days** — long enough that a job outage over a weekend does not silently orphan
objects again, short enough to bound the row count.

Existing orphans are out of scope for this spec: the keys are unreferenced, so
removing them means a bucket listing and a one-off script. Flag it as follow-up
work; do not attempt it here.

---

## 2. Reactions

A fixed emoji row on the story viewer: ❤️ 😂 😮 😢 🔥 👏. Fixed rather than a
picker because the point is one tap.

**Model.** `Story.reactions: [{ userId, emoji, reactedAt }]`, one per viewer —
reacting again replaces the previous emoji rather than appending.

**Endpoints.**
- `POST /stories/:id/reactions` body `{ emoji }` — upsert this viewer's reaction.
- `DELETE /stories/:id/reactions` — remove it.

Both go through `canView`, so the matches-only rule is enforced on the same path
the viewer already passes.

**Notification.** Reuse the existing push machinery with a new type. Gated on
the author's existing notification settings; no new consent field.

**Author view.** The author sees reactions on their own story: emoji and who
sent it. Nobody else sees another viewer's reaction — a story is not a public
post and a reaction is not a like count.

---

## 3. Replies

**Behaviour.** In the story viewer, a text field. Sending it posts a message to
the existing conversation with that match, using the existing send path — so
blocks, unmatch, muting and push all keep working with no new rules.

If no conversation exists yet, `chatService.openConversation` creates it, which
is what makes this a first-message mechanic rather than a nicety for people
already talking.

**Story context on the message.** Add to `Message`:

```js
storyContext: {
  storyId:      { type: String, default: null },
  captionText:  { type: String, default: null },  // snapshot, max 200
  mediaUrl:     { type: String, default: null },  // reference, NOT a snapshot
}
```

`messageType` stays `'text'`. A new enum value would force every client type
switch to learn about stories for what is decoration on an ordinary message.

**Expiry behaviour — the important part.** `captionText` is copied onto the
message and outlives the story. `mediaUrl` is a reference: the client renders
the thumbnail while the story is alive and falls back to a neutral placeholder
once it is gone, showing `Replied to: "sunset at Ocean Beach"`.

The caption is snapshotted and the photo is not, deliberately. A caption is
text the author wrote; a photo is the thing the 24-hour promise is about. After
section 1, that promise is real, and copying story images into N conversations
would quietly break it again. This keeps the conversation legible without
making anyone's disappearing photo permanent.

**Client detail.** The viewer must pause its progress timer while the reply
field has focus. A story advancing out from under a half-typed reply is the
most obvious way to make this feature feel broken.

---

## 4. Text stories

**Model.** `Story.kind: { type: String, enum: ['photo', 'text'], default: 'photo' }`,
plus `text` (max 200, same cap as `caption`) and `background` (a palette key,
not a free-form colour).

`mediaUrl` and `mediaKey` become optional, required only when `kind === 'photo'`.
Enforce that in the service, not with a schema conditional, so the error is a
`ValidationError` the client already knows how to show.

**Palette.** A named set of six gradients, defined once in Dart and mirrored by
key on the server, which stores only the key. The server never stores a colour:
if the palette changes, existing stories re-render rather than freezing an old
hex value.

The first gradient reuses `AppColors.primary` → `AppColors.accent`, already used
by `StoryGradientRing`, so a text story looks native rather than bolted on.

**Creation.** `create_story_screen` gains a photo/text toggle. Text mode is a
text field over the selected gradient, with a horizontal palette strip.

**Endpoint.** `POST /stories` accepts either `multipart` with a file (today's
path, unchanged) or `application/json` with `{ kind: 'text', text, background }`.

**Viewer.** Renders text stories as text on the gradient; every other behaviour
— progress bar, tap to advance, reactions, replies — is identical.

---

## 5. Highlights

**Behaviour.** Before a story expires, the author pins it to their profile,
where it persists until they remove it.

**Audience — and the consent it requires.** A highlight is **public profile
content**, visible to anyone who sees the profile, including strangers in the
deck. A story was shared with matches for 24 hours. Pinning changes both the
audience and the duration.

The confirmation at pin time must say so plainly — "This will be visible on
your profile to anyone who sees it, including people you have not matched
with" — with an explicit confirm. Not a toggle, not a checkbox defaulted on.
Getting this wrong means a user publishing to strangers a photo they shared
with three matches.

**Model.** New `flame/models/StoryHighlight.js`:

```js
{
  userId:     { type: String, required: true, index: true },
  storyId:    { type: String, required: true },
  mediaUrl:   { type: String, default: null },
  mediaKey:   { type: String, default: null, index: true },
  kind:       { type: String, enum: ['photo', 'text'], required: true },
  text:       { type: String, default: null },
  background: { type: String, default: null },
  caption:    { type: String, default: null },
  createdAt:  { type: Date, default: Date.now },
}
```

No TTL. `mediaKey` is indexed because the sweep in section 1 queries it on
every run.

**Media ownership — no copy.** `utils/s3.js` exposes only `uploadBuffer` and
`deleteObject`; there is no copy operation. Rather than adding one and
duplicating the object, the highlight **references the same key**, and the
sweep skips any key a highlight holds. Storage stays single-copy and the object
is deleted by whoever holds the last reference: unpinning a highlight deletes
the object if the story row is already gone.

**Cap.** Nine highlights per user, matching the existing nine-photo cap, so the
profile has one consistent limit rather than two arbitrary ones.

**Endpoints.**
- `POST /stories/:id/highlight` — pin (author only, story must be unexpired).
- `DELETE /highlights/:id` — unpin, deleting media when nothing else holds it.
- `GET /users/:id/highlights` — public, subject to blocks.

**Display.** A highlights row on `profile_detail_screen` and
`my_profile_screen`, below photos. Tapping opens the existing story viewer in a
read-only mode — no reactions, no replies. A highlight is profile content, not
a live story, and reacting to a months-old pinned photo is not the interaction
this feature is for.

---

## Error handling

- Reacting or replying to an expired story returns `404` — the client refreshes
  the tray rather than showing a stale story.
- A reply whose message send fails leaves no reaction and no partial state; the
  viewer shows the send failure and keeps the typed text.
- Pinning a story that expires mid-request fails with a `ValidationError`.
- Sweep failures are logged and retried on the next tick; one object failing to
  delete must not abort the sweep for the rest.

## Testing

Each section carries its own tests; the ones that matter most:

- **Section 1:** an expired story's S3 object is deleted, not merely its row; a
  highlighted story's object survives the sweep; a sweep that dies between
  object and row deletion leaves a retryable state, not an orphan.
- **Section 2:** reacting twice replaces rather than appends; a non-match cannot
  react.
- **Section 3:** a reply reaches the conversation and creates one if absent; the
  caption survives the story's expiry and the image does not; the viewer's timer
  pauses while the field has focus.
- **Section 4:** a text story round-trips without media; a photo story still
  requires it; an unknown palette key is rejected.
- **Section 5:** the cap holds at nine; unpinning deletes media only when the
  story row is gone; a blocked viewer cannot read highlights.

## Not in this spec

- Removing the existing orphaned objects (needs a bucket listing and a one-off
  script).
- Video stories, mentions, per-viewer view timestamps, close-friends tiers —
  all present in BananaTalk, none serving the two goals chosen here.
- Tightening `POST /conversations`, which today lets anyone open a conversation
  with anyone unblocked. Noted while designing this and worth its own decision;
  it is not made worse by anything here.

## Sequencing

Build in order: 1, then 2, then 3, then 4, then 5. Section 1 is a prerequisite
for 5 and makes 3's privacy reasoning true. Sections 2 and 3 deliver the
conversation goal and can ship before 4 and 5 exist.
