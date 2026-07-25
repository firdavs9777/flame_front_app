# Flame — Honest MVP Pre-Prod Readiness — Design Spec

> Date: 2026-07-26 · Branch: `feat/phase-a-visual-foundation`
> Scope decision: **Honest MVP**, covering **both** the Flutter frontend (`~/Desktop/Flame/flame_front_app`)
> and the flame Node/Express backend (`~/Projects/BananaTalk/backend/flame`).

## 1. Goal

Get Flame to a state where it can be deployed to production **honestly and safely**: every
feature the user can see must actually work. Features that have no real backend yet
(chat/messaging, tap-to-translate, social login, forgot-password) are **cleanly hidden or
feature-flagged off**, not shown in a broken state.

**Definition of done (the shippable loop):** a user can
register → build a profile with photos → browse Discover → like/super-like → view *real*
Stories → report/block bad content. Nothing visible lies to the user.

## 2. Why this scope

The audit (Section 4) established that the Flutter frontend is built well but runs far ahead
of the backend — most "features" are complete UIs wired to endpoints that are stubs or don't
exist. A full-featured launch (real messaging + websocket, translate, social auth, real
matching) is multi-week backend work. The Honest MVP path ships the parts that are real now,
hides the rest, and fixes the safety/compliance/correctness blockers — the fastest path to a
deploy we won't be ashamed of.

## 3. Backend reality (empirically verified 2026-07-26 against prod)

Prod was healthy at audit time (`GET /health` → `dbStatus: connected`); demo login works.

Confirmed casing split via live calls:
- **camelCase:** `/auth/login`, `/auth/register`, `GET /users/me` (`lookingFor`, `isOnline`,
  `isVerified`, `lastActive`, `createdAt`; tokens `accessToken`/`refreshToken`/`expiresIn`).
- **snake_case:** `/discover`, `/matches`, `/conversations`, `/swipes`, `/stories`, `/billing/status`.

Endpoint status:

| Endpoint | Reality |
|---|---|
| `POST /auth/{register,login,refresh,logout}` | ✅ real (camelCase) |
| `POST /auth/verify-email`, `/resend-verification`, `/forgot-password`, `/{google,apple,facebook}` | ❌ do not exist |
| `GET /users/me`, `/users/:id`, `PATCH /users/me` | ✅ real (camelCase) |
| `POST /users/me/photos` | 🔴 real route but returns `INTERNAL` in prod (Spaces misconfig) |
| `PATCH /users/me/preferences`, `/users/me/location` | ❓ not in known-real set — verify / likely 404 |
| `GET /discover` | ✅ real (snake_case) |
| `POST /swipes/{like,pass,super-like,undo}` | ⚠️ stub — `is_match` always false |
| `GET /matches`, `GET /conversations` | ⚠️ stub — valid but always empty |
| messaging (`.../messages` send/list, edit/react/read) | ❌ do not exist |
| `POST /translate` | ❌ does not exist |
| `GET/POST/DELETE /stories/*` | ✅ real (snake_case, 24h TTL) — **but frontend never calls them** |
| `GET /billing/status` | ⚠️ stub (free/premium fields, no IAP) |
| `/reports`, `/blocks` | ✅ real (per `ReportService`) — **but no UI calls them** |

## 4. Audit findings (what drove the plan)

### Authentication
- **P0:** Registration dead-ends on the email-verify step. After register the backend issues
  tokens immediately, then the flow pushes `StepVerifyEmail`, which POSTs to non-existent
  `/auth/verify-email`; every code entry returns "Invalid verification code" — the user cannot
  advance. (`registration_flow.dart:360-378`, `step_verify_email.dart:106-157`)
- **P1:** Social login (`/auth/{google,apple,facebook}`) and forgot-password
  (`/auth/forgot-password`) call endpoints that don't exist; social methods also parse tokens
  snake_case-only and would NPE. (`auth_service.dart:175,237,275,311`)
- **P1:** Tokens stored in plaintext `SharedPreferences` (`api_client.dart:56-69`).
- **P1:** `print()` dumps response bodies (tokens + PII) in release (`api_client.dart:440-449`).
- **P1:** Legal docs are lorem-ipsum with a self-declared placeholder banner
  (`legal_document_sheet.dart:88-178`).
- **P1:** `SocialProfileCompletionFlow` is effectively dead (backend never returns
  `is_profile_complete`, so `_statusFor` resolves everyone to `authenticated`).

### Profile
- **P0:** No profile photo can be uploaded in prod — `POST /users/me/photos` → `INTERNAL`
  (Spaces). Both upload paths only show a generic snackbar. (`user_service.dart:121-134`)
- **P1:** Casing mismatch silently defaults `looking_for`/online/verified/preferences, and a
  successful profile save visibly resets Looking-For to "Other". (`user.dart:106-129`,
  `edit_profile_screen.dart:468-479`)
- **P1:** Photo delete + set-as-main are TODO stubs; upload discards `Photo.id`.
  (`edit_profile_screen.dart:312,320`, `user_provider.dart:100-102`)
- **P1:** Profile-detail like/super-like buttons are no-ops (`profile_detail_screen.dart:249-263`).
- **P1:** `updatePreferences`/`updateLocation` hit unconfirmed endpoints.
- **P2:** Hardcoded always-on "verified" badge (`profile_card.dart:182-186`).

### Chat
- **P0:** No messaging backend at all. `/matches` & `/conversations` are empty stubs → Messages
  tab only ever shows the empty state; the thread screen is unreachable via normal nav.
- **P0:** If a thread is reached, sending **clears the input before the (guaranteed-failing)
  network call** and shows a red error — data loss, no optimistic echo.
  (`chat_screen.dart:158,182`, `chat_provider.dart:206`)
- **P1:** All rich-send paths, `markAsRead` on temp conversations (throws), and match-circle
  temp conversations using `match.id` as a conversation id are broken.
- **P1:** Tap-to-translate always fails ("translation unavailable").
- **P2:** Large dead-code stack shipped: `chat_v2_screen.dart` + entire `lib/realtime/*`
  socket.io stack, both unreferenced.

### Community (Discover + Stories)
- **P0:** Stories are 100% mock — `storyServiceProvider` is hardwired to `MockStoryService`;
  no `ApiStoryService` exists; the real `/stories/*` is never called; tray shows fabricated
  picsum images. (`story_provider.dart:11`, `story_service.dart:88-130`)
- **P0:** No report/block UI anywhere — `ReportService` is fully built but has zero callers.
  App Store guideline 1.2 / Play UGC-safety blocker. (`report_service.dart`)
- **P1:** Matching is dead-ended — `/swipes` returns `is_match: false` always → a match can
  never occur → "It's a Match!" dialog unreachable, chat has nothing to open.
- **P1:** Gender/interests/online-only filters are collected but never sent to the API.
  (`filter_provider.dart:49-56`)
- **P1:** Super-like "remaining" counter is fiction (always null from stub).

### Cross-cutting / ops
- Every deploy knocks the flame DB to `disconnected` (needs `pm2 restart language`).
- `MockDataService` is dead code but present.

## 5. Plan (A→Z), ordered by dependency

Each item notes owner: **FE** (Flutter), **BE** (flame backend), **content** (you).

### Phase 0 — Ops & foundation *(unblocks everything)*
- **A. [BE]** Fix `flame/db.js` to reconnect reliably on restart so deploys stop dropping the
  DB. *Acceptance:* deploy to `main`, then `GET /health` returns `dbStatus: connected`
  without a manual `pm2 restart language`; login works immediately post-deploy.
- **B. [BE]** Fix DigitalOcean Spaces config so `POST /users/me/photos` succeeds.
  *Acceptance:* uploading a photo returns a real Spaces URL; the same path is reused by story
  create. Unblocks Phase 3-I and Phase 4-L.

### Phase 1 — Auth: honest & safe
- **C. [FE]** Remove the email-verify step from the registration flow; register transitions
  straight to authenticated. *Acceptance:* a new user completes registration and lands in the
  app with no un-satisfiable code screen.
- **D. [FE]** Hide social-login buttons and the forgot-password entry (no backend). Remove or
  park the `SocialProfileCompletionFlow` path. *Acceptance:* login/welcome screens show no
  control that hits a non-existent endpoint.
- **E. [FE]** Move access/refresh tokens to `flutter_secure_storage` (Keychain/Keystore).
  *Acceptance:* tokens no longer readable from plaintext SharedPreferences; login/refresh/
  logout still work across app restarts.
- **F. [FE]** Gate all `print()` of response bodies/tokens/PII behind a debug flag (off in
  release). *Acceptance:* release build logs contain no tokens or PII.
- **G. [content+FE]** Replace lorem-ipsum Terms/Privacy with real, counsel-approved copy;
  confirm a hosted privacy-policy URL for the stores. *Acceptance:* `LegalDocumentSheet` shows
  final copy; no placeholder banner.

### Phase 2 — Casing reconciliation *(cross-cutting, high value)*
- **H. [FE]** Make `User.fromJson` and token parsing dual-tolerant (accept camelCase **and**
  snake_case). Confirm `PATCH /users/me` write body casing matches what the backend reads.
  *Acceptance:* `/users/me` renders real Looking-For / online / verified / preferences; saving
  the profile no longer resets Looking-For to "Other".

### Phase 3 — Profile: complete
- **I. [FE]** Implement photo delete + set-as-main (replace TODO stubs); capture and retain
  `Photo.id` on upload. *(Depends on B.)* *Acceptance:* user can add, delete, and set a main
  photo; changes persist across reload.
- **J. [FE]** Wire (or remove) the profile-detail like/super-like buttons. *Acceptance:* the
  buttons either perform a real swipe action or are absent — no silent no-ops.
- **K. [FE+BE]** Confirm/implement `PATCH /users/me/preferences` and `/users/me/location`
  (or fold into `PATCH /users/me`); remove the hardcoded always-on "verified" badge (gate on
  `isVerified`). *Acceptance:* preference/location writes persist; the verified badge reflects
  the real field.

### Phase 4 — Community: real Stories + safety
- **L. [FE]** Implement `ApiStoryService` against real `/stories/*`; swap `storyServiceProvider`
  from `MockStoryService`. *(Create depends on B.)* *Acceptance:* the tray shows real stories
  from the backend; a created story is visible to others and expires at 24h; app restart does
  not lose/fabricate stories.
- **M. [FE]** Add Report + Block UI wired to `ReportService`, reachable from profile cards,
  profile detail, and the story viewer. *Acceptance:* a user can report and block from each
  surface; a blocked user's content disappears. **Store-safety gate.**
- **N. [FE+BE]** Send gender/interests/online-only filters through to the API (extend the
  preferences payload + have `/discover` honor them), or hide filters the backend can't honor.
  Age/distance already work. *Acceptance:* every filter shown in the UI actually affects the
  deck, or is not shown.
- **O. [FE]** Neutralize the fake super-like "remaining" counter — hide the gating or make it
  reflect a real value. *Acceptance:* no UI implies a quota the backend doesn't enforce.

### Phase 5 — Chat: hide cleanly
- **P. [FE]** Feature-flag Chat off for prod: **remove the Chat tab** (nav goes 4→3 tabs, since
  matches can't occur yet). Hide the tap-to-translate UI. *Acceptance:* no chat/translate
  surface is reachable in a prod build; nav is coherent with 3 tabs.
- **Q. [FE]** Delete/quarantine dead code: `chat_v2_screen.dart` and the entire `lib/realtime/*`
  socket.io stack; remove unused `MockDataService`. *Acceptance:* `flutter analyze` clean; no
  references to the removed files.

### Phase 6 — Verify & release
- **R. [FE]** Confirm in-app account deletion exists (App Store account-deletion requirement)
  and an 18+ age gate is present; add if missing. *Acceptance:* a signed-in user can delete
  their account in-app; age gate present at sign-up.
- **S. [both]** `flutter analyze` clean + `flutter test` green (update tests for the changed
  registration/chat/stories flows); backend `node --test flame/__tests__/*.test.js` green.
- **T. [FE]** Manual prod smoke: register → profile + photo → discover → like → stories →
  report/block. *Acceptance:* the full DoD loop passes on a release build against prod.
- **U. [both]** Deploy backend → `GET /health` `connected` (no manual restart needed after A)
  → re-run the smoke test.

## 6. Resolved in-plan decisions

1. **Chat tab:** removed entirely for MVP (3 tabs), not kept as a "coming soon" state.
2. **Forgot-password:** hidden for MVP, not built.
3. **Casing:** fixed on the frontend (dual-tolerant reader), not by a backend snake_case
   rewrite — smaller, lower-risk, unblocks immediately. A backend-wide casing normalization is
   explicitly out of scope for this MVP.

## 7. Out of scope (explicitly deferred)

- Real messaging backend + websocket/realtime, tap-to-translate backend, social auth backend,
  email verification, real matching (Swipe model + mutual-match detection). These return when
  a future "full-featured" milestone is scoped.
- Stories matches-only visibility (stays all-users until real matching exists; single swap
  point at `storyService.visibleAuthorFilter`).
- In-app purchases / premium billing.

## 8. Risks & dependencies

- **Phases 3-I and 4-L depend on Phase 0-B** (Spaces fix). If B slips, profile-photo and
  story-create remain blocked — do not ship without B.
- **Phase 0-A** is the top ops risk: until it's fixed, the release deploy in Phase 6-U will
  itself take login down until a manual restart.
- **Phase 4-M (report/block)** and **1-G (legal)** and **6-R (account deletion / age gate)**
  are store-review gates — missing any one likely means rejection, independent of functionality.
