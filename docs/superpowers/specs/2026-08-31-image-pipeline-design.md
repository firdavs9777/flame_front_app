# Image pipeline — right-sized images, and an event loop that stops stalling

Spans both repositories. Backend: `app/core/storage.py`, a new `app/core/images.py`,
`app/models/user.py`, `app/users/routes.py`, `Dockerfile`, and a new
`tool/backfill_photo_variants.py`. App: `lib/widgets/smart_image.dart`,
`lib/widgets/kit/app_avatar.dart`, `lib/core/image/`, the swipe deck, and the
chat attachment picker.

This is sub-project A of six. The full audit covered Discover, chat, location,
notifications, email scheduling and images; the other five are sequenced behind
this one because this is the only one that is felt on every screen and needs no
new infrastructure. B (location hardening), C (Discover quality), D (push) and
E (email + job runner) get their own specs.

The reported symptom was "images load slowly" on the swipe deck, the matches and
chat lists, profile screens, and photo upload. All four at once is the useful
signal: it points at systemic causes rather than one bad screen, and one of the
causes turns out not to be about images at all.

## Why

**Synchronous boto3 runs inside `async def`, on a single worker.** `put_object`
(`storage.py:58`, `storage.py:85`) and `delete_object` (`storage.py:103`) are
blocking calls with no `run_in_executor`, no `asyncio.to_thread`, and no
aioboto3, invoked directly from async routes. `Dockerfile:25` runs `uvicorn`
with no `--workers` flag.

So every photo upload blocks the entire event loop for the full round trip to
Spaces. One person uploading a photo stalls every other request on the only
worker: deck fetches, chat sends, WebSocket frames. `update_profile_picture`
compounds it — `users/routes.py:72` does a blocking `delete_object` for the old
primary and then `users/routes.py:57` a blocking `put_object`, serially, after
`await file.read()` has pulled the whole file into memory.

This is almost certainly why all four surfaces feel slow rather than only the
image-heavy ones. It is an image problem and a concurrency problem sharing one
module.

**One file serves every size.** `storage.py` does a raw `put_object` on the
bytes it was handed. There is no resize, no thumbnail, no variant, no WebP.
Pillow sits in `requirements.txt` and is used for nothing. The same 1024px JPEG
is the full-bleed deck card, the `radius: 32` matches-grid avatar
(`matches_screen.dart:313`) and the `radius: 28` chat-row avatar
(`matches_screen.dart:413`). A matches list downloads N full-size photos to draw
N circles.

**Nothing decodes at draw size.** `smart_image.dart:56` and
`app_avatar.dart:147` both construct a `CachedNetworkImage` with no
`memCacheWidth`, so every image decodes at full resolution — 1024x1024 is
roughly 4MB of RAM per image, held for a 64pt circle. `SmartImage` is the
renderer for `profile_card.dart:86`, `profile_detail_screen.dart:86`,
`my_profile_screen.dart:419`, `photos_section.dart:100` and `:146`, and
`story_viewer_screen.dart:142`.

This exact bug was already found and fixed once. `core/image/avatar_provider.dart`
exists because "a 2000px profile photo was being decoded and uploaded to the GPU
to fill a 40px circle — at every avatar site in chat, because only
`message_bubble.dart` ever passed `memCacheWidth`." The fix was scoped to chat
avatars. Everywhere else still has the bug.

**The deck does not prefetch.** Card N+1's image begins downloading when it
becomes visible, which is the moment it is too late.

**No `Cache-Control` is set on upload.** `put_object` passes `ContentType` and
`ACL` and nothing else, so the CDN and the client fall back to whatever DO
Spaces defaults to and revalidate more than they need to. The keys already
contain a millisecond timestamp and a UUID (`storage.py:_build_key`), so they
are genuinely immutable and could say so.

**`MAX_PHOTO_SIZE` and `MAX_PHOTOS_PER_USER` are dead config.** Defined at
`config.py:35` and `config.py:37`, referenced nowhere. `validate_image_file`
(`users/routes.py:25`) checks `content_type` and returns. The social-signup path
at `auth/service.py:56` accepts base64 image payloads with no ceiling of any
kind.

**Chat image attachments have no dimension cap.** `chat_attachments.dart:42`
and `:44` pass `imageQuality: 85` and no `maxWidth`/`maxHeight`, so a 12MP
camera photo uploads at 12MP. Profile photos are capped at 1024x1024
(`step_photos.dart:469`, `photos_section.dart:288` and `:304`); chat images are
not.

**EXIF survives the round trip.** Nothing re-encodes an uploaded photo, so
whatever the camera embedded — including GPS coordinates — is served publicly
from a CDN. In a dating app that is a safety problem, not a tidiness one. It is
listed here rather than in a scope of its own because re-encoding through Pillow
closes it as a side effect, and it would be strange to do the work and not say
so.

## Deployment constraint

Backend `d480c8c` and app `1.0.0+10001` both went out on 2026-08-30. Local HEAD
matches deployed on both sides. There are live clients in the field, and that
governs the shape of this work more than any technical preference.

**The additive change is safe, and this was verified rather than assumed.**
`User.fromJson` (`lib/models/user.dart:121`) parses each photo entry as either a
bare URL string or a `{url, id}` object and ignores keys it does not recognise.
Adding `url_medium` and `url_thumb` to the serialised `Photo` is therefore
invisible to `1.0.0+10001`, and the backend can ship first.

**`url` must keep pointing at the object it already points at.** The backfill
adds variants beside the original and never rewrites `url` or deletes the key it
names. Rewriting it to a new WebP key would 404 every photo on every installed
client at once. This is the single rule in this document that cannot be relaxed.

A consequence worth stating plainly: **WebP and the raised 1440 cap apply only
to new uploads from a new client build.** Existing photos keep the 1024 JPEG
they have at `url` and gain small variants generated from it. Existing users
therefore keep full-size avatars until they update to Deploy 2.

**`--workers` is safe, and this was the risk worth checking.** In-memory
connection state plus multiple workers is a standard way to break chat silently.
Every outbound message in `chat/websocket.py` goes through
`redis_pubsub.publish`, and local delivery happens only inside
`handle_redis_message` (`websocket.py:98`). No path performs a direct local
broadcast *and* a publish, so there is no duplicate-send. Presence is
Redis-backed with a TTL (`cache.py:221`), not per-process. The lifespan runs per
worker, giving each its own Mongo connection and its own pubsub listener, which
is what the fan-out already assumes. `_drop_conflicting_indexes`
(`database.py:14`) will run in every worker at boot; it is conditional and
try/except-wrapped and Mongo's `createIndexes` is idempotent, so racing workers
produce at most a logged warning.

### Two deploys

**Deploy 1 — backend only, no client change required.** Non-blocking boto3,
`--workers`, `Cache-Control`, `MAX_PHOTO_SIZE` enforcement, variant generation
on new uploads, additive model fields, then the backfill.

**Deploy 2 — the app.** Variant consumption, decode sizing, deck prefetch,
raised upload cap, chat attachment cap.

The ordering matters: the event-loop fix is the largest single win and it
reaches production without waiting on store review.

## The variant ladder

The current client cap is 1024x1024. A deck card is full-bleed — roughly 390pt
at 3x is 1170 physical pixels — so today's original is already being *upscaled*
on the card. Shrinking it further would make the deck worse. The cap goes up,
and the savings come from the small sizes.

| Field | Long edge | Consumers |
|---|---|---|
| `url` | 1440 | deck card, profile detail, gallery, media viewer |
| `url_medium` | 512 | edit-profile grid, profile previews |
| `url_thumb` | 256 | matches grid, chat rows, every avatar |

WebP at q82, which is roughly 30% smaller than equivalent JPEG and is decoded
natively by Flutter on iOS, Android and web. A 20-avatar matches list goes from
20 full-size JPEGs to 20 256px WebPs.

## Design

### `app/core/images.py` (new)

One entry point: `generate_variants(data: bytes) -> dict[str, bytes]`.

Pure. No S3, no FastAPI, no network, no config. That split is the point — variant
generation is where the real logic lives (EXIF orientation, aspect, never
upscaling past the source, quality), and keeping it free of I/O makes it
testable with a synthetic two-pixel image.

Honours EXIF orientation before resizing, or portrait photos come out sideways.
Preserves aspect ratio. Never upscales beyond the source, so a 300px original
yields a 300px "full". Sets `Image.MAX_IMAGE_PIXELS` to reject decompression
bombs.

### `app/core/storage.py` (rewritten)

- Every boto3 call moves behind `asyncio.to_thread`. This is the change that
  stops one upload from stalling every other request.
- The three variants upload concurrently under `asyncio.gather`.
- `CacheControl="public, max-age=31536000, immutable"` on every put. Keys carry
  a timestamp and a UUID, so this is a statement of fact rather than a bet.
- The eight near-identical `upload_message_*` methods collapse into one
  parameterised call. All eight are being touched for the threading change
  anyway, and eight copies of the same four lines is where the next bug hides.

### `app/models/user.py`

```python
class Photo(BaseModel):
    id: str
    url: str
    url_medium: Optional[str] = None
    url_thumb: Optional[str] = None
    is_primary: bool = False
    order: int = 0
```

`Optional` with a `None` default is load-bearing twice over: existing documents
deserialise unchanged, and the client's fallback path means the app ships safely
before the backfill has finished.

### `app/users/routes.py`

`validate_image_file` gains the size check it was always meant to have, against
the `MAX_PHOTO_SIZE` that has been sitting unused in config. `MAX_PHOTOS_PER_USER`
is enforced on the add path. The base64 branch at `auth/service.py:56` gets the
same ceiling.

### `Dockerfile`

Add `--workers`. A single worker is why blocking I/O was catastrophic rather
than merely wasteful.

### Flutter

- **`photoUrlFor(photo, size)`** — the one place that knows variant names and
  falls back to `url` when a variant is absent. Nothing else learns the scheme.
- **`SmartImage` gains a required `decodeWidth`.** Required, not optional,
  following the precedent `avatar_provider.dart` set deliberately: making the
  un-sized version *unavailable* beats making it discouraged. This is the fix
  for the six call sites listed under Why.
- **`AppAvatar`** reads the thumb variant and passes `memCacheWidth`.
- **Deck prefetch** — `precacheImage` for cards N+1 and N+2 when the deck list
  changes, so the next card is warm before it is swiped to.
- **Chat attachments** — `pickImage` gains `maxWidth`/`maxHeight`; bubbles read
  a thumb variant against the existing `kChatMediaWidth = 240`
  (`message_bubble.dart:22`). `message_bubble.dart:650` already passes
  `memCacheWidth` correctly and is left alone.

### `tool/backfill_photo_variants.py` (new)

Run once, after Deploy 1. Walks every user's photos, downloads each original,
generates variants, writes them beside the original, and updates the document.

Idempotent: skips any photo that already has `url_thumb`, so a partial failure
just means running it again. Per-photo `try`/`except` so one corrupt image does
not halt the batch. `--dry-run` reports what it would touch. Prints a summary of
processed, skipped and failed.

## Error handling

Variant generation failing must never fail an upload. On error, store the
original at `url`, leave the variant fields null, and let the client's existing
fallback carry it — a user losing a photo because a resize failed would be a
worse outcome than a slow photo.

A corrupt or hostile image is rejected at validation as a 400, not a 500.

The backfill treats every per-photo failure as recoverable and reports it.

## Testing

`core/images.py` gets pure unit tests: output dimensions per variant, aspect
preserved, EXIF orientation applied, EXIF stripped from output, no upscaling
past source, decompression bomb rejected.

`storage.py` gets an injected fake client asserting that calls are threaded and
that `CacheControl` is set on every put.

Routes: an upload returns all three URLs; an oversize upload is rejected; the
seventh photo is rejected.

Flutter widget tests: `SmartImage` and `AppAvatar` pass a decode width;
`photoUrlFor` falls back to `url` when a variant is null; the deck precaches
ahead of the visible card.

Backfill: a second run is a no-op; a run that dies partway resumes cleanly.

## Out of scope

Video transcoding. Sticker assets. An image CDN proxy or on-the-fly transform
service — evaluated and rejected in favour of upload-time generation, because it
needs no new service to deploy, secure and pay for. The job runner: the backfill
is a script you run, not a queued job, and the runner belongs to sub-project E.
