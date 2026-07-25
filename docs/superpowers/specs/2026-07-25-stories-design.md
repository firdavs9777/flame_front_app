# Stories (Ephemeral, Photos-Only) — Design

**Date:** 2026-07-25
**Status:** Approved for planning
**Scope:** Ephemeral 24-hour photo stories for a dating app. Built frontend-first behind a `StoryService` seam (mock implementation now, real API later). Matches-only visibility; tray lives atop the Chat/Matches tab. A lean port of BananaTalk's Stories, adapted to Flame's Riverpod architecture.

## Background

Flame is a Tinder-style dating app (Riverpod + go_router + socket.io chat). It has **no** Stories backend and no story-related endpoints. BananaTalk has a large Stories feature (~25 files) with an editing studio, polls, reactions, mentions, highlights, video, and close-friends — most of which is additive and not part of the core ephemeral loop. This phase builds only the core loop, photos-only, so it is demoable and testable today and ready to swap onto a real backend later.

### Decisions (from brainstorming)

1. **Purpose:** ephemeral profile stories (Instagram/Snapchat-style), not conversation-prompt "moments".
2. **Backend:** none exists → build frontend-first behind an abstract `StoryService` with a mock implementation. Real `ApiStoryService` is a future drop-in (same interface).
3. **Media:** photos only. No video (drops recording/compression/playback and the viewer's video branch).
4. **Visibility & placement:** stories only from people you've **matched** with (privacy-appropriate for dating); tray is a ring row atop the **Matches/Chat** tab, your own story first with a `+` to add.

### Approach (chosen over alternatives)

**Service-seam + Riverpod.** BananaTalk used ad-hoc `setState` + static service methods with no caching; Flame instead uses an abstract `StoryService` (mock now) plus Riverpod providers, matching the rest of the app. *Rejected:* copying BananaTalk's static-service style (inconsistent with Flame); building straight against a live API (no backend exists).

## Design

### 1. Models (`lib/models/story.dart`)

- `Story`: `id`, `userId`, `mediaUrl`, `caption` (nullable), `createdAt`, `expiresAt`, `viewCount`, `hasViewed`. Photos-only, so no video/text-story fields. `bool get isActive => expiresAt.isAfter(DateTime.now())`. `fromJson`/`toJson` for the future API.
- `UserStories`: `userId`, `name`, `avatarUrl`, `List<Story> stories`. Computed: `activeStories` (24h filter), `hasUnviewed` (any active story with `!hasViewed`), `latestAt` (for tray ordering).

### 2. Service seam (`lib/services/story_service.dart`)

Abstract `StoryService`:
- `Future<List<UserStories>> feed()` — matches' active stories grouped by user (excludes expired).
- `Future<UserStories?> myStories()` — the current user's own active stories.
- `Future<Story> create({required File image, String? caption})` — upload a photo, returns the created story (expires 24h out).
- `Future<void> markViewed(String storyId)` — record a view.
- `Future<void> delete(String storyId)` — remove own story.

`MockStoryService implements StoryService` — in-memory store seeded with a few matched users' active stories (drawing names/avatars from the existing mock data pattern). Supports create (adds to own, local file path as `mediaUrl`), `markViewed` (flips `hasViewed`, bumps `viewCount`), delete, and 24h expiry filtering. Deterministic seed for testability.

`storyServiceProvider` (Riverpod `Provider<StoryService>`) returns `MockStoryService` now. Swapping to a real `ApiStoryService` (implementing the same interface against `/stories/*` via `ApiClient`) is a one-line change; that implementation is out of scope here.

### 3. State (Riverpod)

- `storiesFeedProvider` — `AsyncNotifierProvider<StoriesFeedNotifier, List<UserStories>>`. Loads own + matches' stories via `storyServiceProvider`; own entry first, then matches with `hasUnviewed` ranked above seen. Exposes `refresh()`; invalidated after `create` and after `markViewed` so rings update.
- Viewer playback is local UI state (an `AnimationController` in `StoryViewerScreen`), not a global provider — it's ephemeral per-open and doesn't need to survive rebuilds.

The feed derives "who are my matches" from the existing `matchesProvider`; the mock service seeds stories for a subset of those matched users.

### 4. UI

- **`StoryTray`** (`lib/screens/stories/widgets/story_tray.dart`) — a horizontal, scrollable ring row placed at the top of the Matches/Chat screen (`matches_screen.dart`), above the existing list. First item: the current user's avatar with a `+` badge (add a story) or their own ring if they have an active story. Other items: matched users, showing a **coral gradient ring** (`AppColors.primaryGradient`) when `hasUnviewed`, grey when all seen. Built on the kit's `AppAvatar`. Tapping an item opens the viewer at that user; tapping own `+` opens create. Hidden/empty-safe when there are no stories (still shows own `+`).
- **`StoryViewerScreen`** (`lib/screens/stories/story_viewer_screen.dart`) — full-screen pager over the tapped user's active stories, then advancing to the next user in the feed (or closing at the end). Behaviors ported from BananaTalk: segmented progress bars (one per story, current fills over time), **5s auto-advance** per photo via `AnimationController`, tap-zones (left 30% → previous, right 70% → next), **hold-to-pause** (`onLongPressStart`/`End` pause/resume the controller), **swipe-down-to-dismiss** (`onVerticalDragUpdate` accumulates; dismiss past ~100px or a fast fling) with a transform+fade. Uses `cached_network_image`. Fires `markViewed(storyId)` when a story becomes visible. Broken image → skip with a placeholder.
- **`CreateStoryScreen`** (`lib/screens/stories/create_story_screen.dart`) — `image_picker` (camera or gallery) → preview the chosen photo with an optional caption `TextField` (uses the kit's `AppInput`) → post button (`AppButton`) calls `create` then refreshes the feed and pops. No cropping/filters/drawing/stickers.
- **Reusable widgets**: `StoryGradientRing` (ring around an avatar), `StoryProgressBar` (segmented). Both small, in `lib/screens/stories/widgets/`.

New user-facing strings (tray label, "Add to story", "Your story", caption hint, post button, delete confirm) are localized across all 12 ARBs.

### 5. Error handling

- Create/upload failure → snackbar (localized), stay on the create screen so the user can retry.
- Feed load failure → the tray shows a compact retry affordance; the rest of the Chat screen is unaffected.
- View/delete failure → silent for view (best-effort); delete failure → snackbar.
- Broken/missing image in the viewer → placeholder and auto-advance.

### 6. Testing

- **Model**: `Story.isActive` expiry boundary; `UserStories.hasUnviewed`/`activeStories` filtering.
- **MockStoryService**: `create` adds to own stories with a 24h expiry; `markViewed` flips `hasViewed` and bumps `viewCount`; expired stories are excluded from `feed`; `feed` returns only matched users; `delete` removes.
- **Widget**: `StoryTray` renders an unviewed (gradient) vs seen (grey) ring and the own-`+`; `StoryViewerScreen` advances on right-tap and calls `markViewed`; swipe-down dismisses.

## Non-goals (explicitly deferred)

Video stories; highlights (persistent, profile-grouped); the editing studio (crop/filters/drawing/text overlays/gradient text stories/stickers); polls & question boxes; reactions & replies; mentions, location, music, links, hashtags; close-friends/privacy tiers; the viewers-list sheet; share-to-chat. The `StoryService` interface leaves room to grow into these.

## Risks

- **No backend** → `MockStoryService` makes the feature fully functional in-app; the real `ApiStoryService` is a future drop-in behind the same interface. No user-facing breakage in the meantime.
- **Viewer gesture complexity** → the five behaviors (timer, tap-zones, hold-pause, progress, swipe-dismiss) are the riskiest surface; they're isolated in `StoryViewerScreen` and covered by widget tests for the tap-advance and dismiss paths.
- **Mock persistence** → mock stories live in memory for the session (created stories vanish on restart); acceptable for a frontend-first slice and called out so it isn't mistaken for a bug.
