# Flame API — Translate & Stories (Backend Contract)

Addendum to `API_DOCUMENTATION.md`. These endpoints back two features whose
Flutter clients are **already implemented** against a service seam; this
document is the exact contract the backend must satisfy so the clients light up
unchanged.

Follow the same conventions as the main doc:
- **Base URL**: `https://api.flame.app/v1` (client uses `EnvConfig.current.apiBase`).
- **Auth**: `Authorization: Bearer <access_token>` (JWT) on every endpoint here.
- **Success envelope**: `{ "success": true, "data": { ... } }`. The client unwraps `data` (`ApiResponse` reads `body.data ?? body`).
- **Error envelope**: `{ "success": false, "error": { "code": "...", "message": "...", "details"?: {...} } }`.
- **Field casing**: `snake_case` (the client models parse snake_case keys).

---

## Translation Endpoint

### 40. Translate Text

Translates a chat message's text into a target language. Called when a user
taps "Translate" under an incoming message.

**Endpoint**: `POST /translate`

**Request Body**:
```json
{
  "text": "Hola, ¿cómo estás?",
  "target_lang": "en",
  "source_lang": "es"
}
```

**Fields**:
- `text` (string, required): the message text to translate. Non-empty; the client already trims and rejects empty input before calling.
- `target_lang` (string, required): ISO 639-1 code of the desired language (`en`, `ja`, `ko`, `zh`, `tr`, `id`, `es`, `pt`, `fr`, `de`, `ru`). Sourced from the user's app locale.
- `source_lang` (string, optional): ISO code of the source language. **Omit to let the backend auto-detect.**

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "translated_text": "Hello, how are you?",
    "detected_source_lang": "es",
    "target_lang": "en"
  }
}
```

**Fields the client reads**: `translated_text` (primary). For resilience the client also accepts `translation` or `text` as the key — but **return `translated_text`**. `detected_source_lang` and `target_lang` are optional/ignored today.

**Errors**:
- `400 VALIDATION_ERROR` — missing/empty `text` or `target_lang`.
- `429 RATE_LIMITED` — per-user translation quota exceeded. Include a `Retry-After` header (seconds). The client already maps this code to a localized "doing that too often" message.
- `502 TRANSLATION_FAILED` — upstream translation provider error. The client shows "Translation unavailable".

**Notes**:
- The client caches each message's translation in memory for the session (one call per message). The backend may add its own text+lang cache to cut provider cost.
- Keep latency reasonable (< ~2s) — the UI shows an inline spinner while awaiting.

---

## Stories Endpoints

Ephemeral photo stories, active for **24 hours**. Visibility is **matches-only**:
a story is visible to the author and to users the author has matched with. The
server enforces this — the client never sends a viewer list.

### Story object (shared shape)

Returned wherever a story appears. Matches the client `Story.fromJson`:
```json
{
  "id": "sty_abc123",
  "user_id": "usr_abc123",
  "media_url": "https://cdn.flame.app/stories/sty_abc123.jpg",
  "caption": "sunset run 🌅",
  "created_at": "2026-07-25T18:04:00Z",
  "expires_at": "2026-07-26T18:04:00Z",
  "view_count": 12,
  "has_viewed": false
}
```
- `caption` is nullable.
- `expires_at` = `created_at + 24h` (server-set).
- `has_viewed` is **relative to the requesting user**.

### User-stories group (shared shape)

The tray/feed groups a user's active stories. Matches the client `UserStories`:
```json
{
  "user_id": "usr_def456",
  "name": "Ava",
  "avatar_url": "https://cdn.flame.app/u/def456/1.jpg",
  "stories": [ { /* Story object */ } ]
}
```

### 41. Get Stories Feed

Active stories from the authenticated user's **matches**, grouped per user.
Only users who have at least one non-expired story are included. The server
should return them oldest-story-first within each user; the client re-sorts
groups (unseen first).

**Endpoint**: `GET /stories/feed`

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "users": [
      {
        "user_id": "usr_def456",
        "name": "Ava",
        "avatar_url": "https://cdn.flame.app/u/def456/1.jpg",
        "stories": [ { /* Story object */ } ]
      }
    ]
  }
}
```

### 42. Get My Stories

The authenticated user's own active stories.

**Endpoint**: `GET /stories/my`

**Response (200 OK)**:
```json
{
  "success": true,
  "data": {
    "user_id": "usr_abc123",
    "name": "You",
    "avatar_url": "https://cdn.flame.app/u/abc123/1.jpg",
    "stories": [ { /* Story object */ } ]
  }
}
```
Return `"stories": []` (or `data: null`) when the user has no active stories.

### 43. Create Story

Upload a photo story. **`multipart/form-data`** (not JSON), because it carries
an image file.

**Endpoint**: `POST /stories`

**Content-Type**: `multipart/form-data`

**Form fields**:
- `media` (file, required): the photo (JPEG/PNG/WebP). Enforce a size cap (e.g. 10 MB) and re-encode/strip EXIF server-side.
- `caption` (string, optional): max ~200 chars.

**Response (201 Created)**:
```json
{
  "success": true,
  "data": { /* Story object, with server id/media_url/created_at/expires_at */ }
}
```

**Errors**:
- `400 VALIDATION_ERROR` — no `media`, or unsupported type.
- `413 FILE_TOO_LARGE` — exceeds the size cap.

### 44. Mark Story Viewed

Records that the authenticated user viewed a story. Idempotent — repeated calls
for the same (viewer, story) count once. Fired by the viewer as each story is
shown; failures are best-effort (the client ignores errors here).

**Endpoint**: `POST /stories/{story_id}/view`

**Response (200 OK)**:
```json
{
  "success": true,
  "data": { "view_count": 13 }
}
```

**Errors**:
- `404 STORY_NOT_FOUND` — unknown/expired story.
- `403 STORY_FORBIDDEN` — the story's author is not matched with the viewer.

### 45. Delete Story

Deletes the authenticated user's own story.

**Endpoint**: `DELETE /stories/{story_id}`

**Response (200 OK)**:
```json
{ "success": true, "data": { "deleted": true } }
```

**Errors**:
- `404 STORY_NOT_FOUND`.
- `403 STORY_FORBIDDEN` — not the author.

---

## New Error Codes (add to the Error Codes table)

| Code | HTTP | Meaning |
|---|---|---|
| `RATE_LIMITED` | 429 | Translation quota exceeded (already used elsewhere; reuse). |
| `TRANSLATION_FAILED` | 502 | Upstream translation provider failed. |
| `STORY_NOT_FOUND` | 404 | Story id unknown or expired. |
| `STORY_FORBIDDEN` | 403 | Not the author (delete) or not matched (view). |
| `FILE_TOO_LARGE` | 413 | Uploaded media exceeds the size cap. |

---

## Client mapping (for reference)

How the existing/imminent Flutter clients call these — implement to match:

| Client method | Endpoint |
|---|---|
| `TranslationService.translate(text, targetLang, sourceLang?)` | `POST /translate` |
| `StoryService.feed()` | `GET /stories/feed` |
| `StoryService.myStories()` | `GET /stories/my` |
| `StoryService.create(image, caption?)` | `POST /stories` (multipart) |
| `StoryService.markViewed(storyId)` | `POST /stories/{id}/view` |
| `StoryService.delete(storyId)` | `DELETE /stories/{id}` |

**Translation** is wired now (`lib/services/translation_service.dart`) and will
work the moment `POST /translate` exists. **Stories** currently run on
`MockStoryService`; once these endpoints exist, add an `ApiStoryService`
implementing the same `StoryService` interface (in `lib/services/story_service.dart`)
and point `storyServiceProvider` at it — a one-line swap, no UI changes.

## Server-side requirements checklist

- Enforce **matches-only** visibility on feed/create-visibility/view.
- Set `expires_at = created_at + 24h`; exclude expired stories from all reads.
- Compute `has_viewed` per requesting user; `view_count` is the distinct viewer count.
- Store media on a CDN; return absolute `media_url`s; strip EXIF; cap file size.
- Rate-limit translation per user (free quota → `429 RATE_LIMITED`).
- All endpoints require a valid JWT; return `401`/`AUTH_LOST`-family on expiry (client auto-refreshes).
