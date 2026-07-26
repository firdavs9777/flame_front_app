# Flame — Project Overview & Reference

A living reference for the **Flame** dating app: where things live, how to run it,
what's built, and the known gotchas. Read this first when returning to the project.

> Last updated: 2026-07-26

---

## 1. What Flame is

A Tinder-style **dating app**. Swipe to discover, match, chat. Built with Flutter
(frontend) + a Node/Express sub-app (backend), sharing infra with the BananaTalk
language-exchange app.

## 2. Where everything lives (important — there are stale copies!)

| Piece | Path | Notes |
|---|---|---|
| **Frontend (Flutter)** | `~/Desktop/Flame/flame_front_app` | The real app. (NOT `~/Desktop/Personal Study/flutter&dart/flame`, which is an empty starter.) |
| **Backend (real)** | `~/Projects/BananaTalk/backend/flame` | Node/Express **sub-app** of the BananaTalk backend, mounted at `/flamebackend/v1/*`. Isolated: own Mongo conn (`flameConn`/`FLAME_MONGO_URI`), own JWT (`FLAME_JWT_SECRET`), own Spaces bucket (`FLAME_SPACES_BUCKET`). |
| **Backend (stale/ignore)** | `~/Desktop/Flame/flame_backend` | A **FastAPI** copy — NOT used. Ignore it. |

Backend repo: `github.com/firdavs9777/language_exchange_backend_application`, branch **`main`** auto-deploys.

## 3. Tech stack

- **Frontend:** Flutter, Riverpod, go_router, `just_audio`, `cached_network_image`, `image_picker`, `flutter_animate`, i18n (11 locales), `intl`.
- **Backend:** Node/Express, Mongoose (MongoDB Atlas), JWT, DigitalOcean Spaces (S3) via `aws-sdk`, `multer`, `zod`. Tests: `node:test` + `supertest` + `mongodb-memory-server`.

## 4. Environments & URLs

`lib/config/env.dart` drives this.

- **Prod API base:** `https://api.banatalk.com/flamebackend/v1`
  - ⚠️ **Do NOT use `https://api.flame.banatalk.com/v1`** — that host has an SSL cert
    mismatch (causes `HandshakeException` on login) and routes to the wrong service.
    Fixing that subdomain (cert + nginx → `/flamebackend/v1`) is a TODO.
- **Local:** `http://<LOCAL_HOST>:8000/v1` — run with `--dart-define=APP_ENV=local`
  (and `--dart-define=LOCAL_HOST=<your-ip>`).
- **Realtime WebSocket:** disabled in prod (`EnvConfig.realtimeEnabled = false`) — the
  flame backend has no chat socket yet.

## 5. Demo account

```
Email:    demo@flame.app
Password: FlameDemo123
```
Live on the flame prod DB. Login returns tokens immediately (no email verification gate).

## 6. Backend API (flame sub-app, `/flamebackend/v1/*`)

Envelope: `{ "success": true, "data": ... }` or `{ "success": false, "error": {code,message} }`.
**Responses that the app parses use snake_case** (see gotcha #2).

| Endpoint | Status | Notes |
|---|---|---|
| `POST /auth/register`, `/auth/login`, `/auth/refresh`, `/auth/logout` | ✅ real | camelCase user shape (mismatch — gotcha #2) |
| `GET /users/me`, `GET /users/:id`, `PATCH /users/me`, `POST /users/me/photos`, `DELETE /users/me/photos/:id` | ✅ real | ⚠️ prod photo upload returns `INTERNAL` (Spaces misconfig) |
| `GET/POST/DELETE /stories/*` (feed, my, create, :id/view, :id) | ✅ real | ephemeral 24h photo stories, TTL index, matches-only-ready (all-users for now) |
| `GET /discover` | ✅ real | returns other users (snake_case) for the swipe deck |
| `POST /swipes/{like,pass,super-like,undo}` | ⚠️ stub | acks only; `is_match` always false (no Swipe model yet) |
| `GET /matches`, `GET /conversations` | ⚠️ stub | valid empty pages (features not built server-side) |
| `GET /billing/status` | ⚠️ stub | free status (no IAP yet) |

Backend module pattern: `routes/*.js` → `controllers/*.js` → `services/*.js`, models in
`models/*.js` (Mongoose on `getConn()`), `middleware/auth.js` sets `req.user`, uploads via
`utils/s3.js`, errors via `utils/errors.js`. Tests in `flame/__tests__/`.

## 7. What was built (2026-07 session)

Frontend (all tested, `flutter test` green, `flutter analyze` clean), specs in `docs/superpowers/specs/`:
- **Phase A — Visual Foundation:** design tokens + 6-widget UI kit (`lib/widgets/kit/`),
  Light/Dark/**System** theme (persisted), restyled tab bar, +5 locales (ja/ko/zh/tr/id → 11).
- **Voice message playback** — `just_audio` + `voicePlaybackProvider` + `VoiceMessagePlayer`.
- **Tap-to-translate** (chat) — `TranslationService` + inline UI (needs a `/translate` backend).
- **Stories** — tray + full-screen viewer (5 gestures) + create, behind a `StoryService` seam.
- **Registration ToS/Privacy consent** — checkbox gate + `LegalDocumentSheet` (placeholder legal copy).
Backend: stories + discover + swipes + matches/conversations/billing stubs.

## 8. Known issues / gotchas (READ THESE)

1. **Deploy takes the flame DB down.** Every push to `main` auto-deploys and the flame
   Mongo connection comes back **`disconnected`** (`health` → `dbStatus: disconnected`,
   login → `INTERNAL`, "buffering timed out"). **Fix each time: `pm2 restart language`.**
   Proper fix TODO: make `flame/db.js` reconnect reliably on restart (connection options /
   retry), or fix the deploy hook. Main BananaTalk DB is unaffected (separate connection).
2. **Casing mismatch.** Frontend models parse **snake_case** (`looking_for`, `is_online`,
   `created_at`, `access_token`); the flame backend's auth/user endpoints emit **camelCase**
   (`lookingFor`, `accessToken`). Login was patched to accept both token casings
   (`auth_service.dart`); secondary user fields still fall back to defaults. **Proper fix:**
   make the backend emit snake_case everywhere (or make `User.fromJson` dual-tolerant).
   New endpoints (stories/discover/swipes) already return snake_case.
3. **`api.flame.banatalk.com` is broken** — cert mismatch + wrong routing. Use
   `api.banatalk.com/flamebackend/v1`. Fix the subdomain someday.
4. **Prod photo upload fails** — `POST /users/me/photos` → `INTERNAL` (flame DO Spaces
   misconfig in prod). Blocks profile completion + registration photo step.
5. **Profile-completion gating** — `auth_provider._statusFor` now trusts the backend
   (`isProfileComplete ?? true`) instead of guessing from photos, so photo-less accounts
   reach main. The backend doesn't return `is_profile_complete` yet.

## 9. Run / test / deploy

**Frontend**
```
cd ~/Desktop/Flame/flame_front_app
flutter run                      # prod by default
flutter run --dart-define=APP_ENV=local --dart-define=LOCAL_HOST=<ip>
flutter test        # unit/widget tests
flutter analyze
flutter gen-l10n    # after editing lib/l10n/*.arb
```
Env/theme changes are `const` → **full restart** (not hot-reload).

**Backend**
```
cd ~/Projects/BananaTalk/backend
node --test flame/__tests__/*.test.js      # flame tests (in-memory Mongo, S3 stubbed)
# deploy: push to main → auto-deploy → THEN `pm2 restart language` (see gotcha #1)
pm2 logs language | grep -i "flame\|Mongo"  # watch for "🔥 [flame] MongoDB connected"
```

## 10. Roadmap / TODO

- **Fix the deploy → flame-DB-disconnect** (gotcha #1) — highest priority; deploys currently take login down.
- Reconcile **snake_case vs camelCase** app-wide (gotcha #2).
- Fix `api.flame.banatalk.com` cert/routing; fix prod photo upload (Spaces).
- Real **matches** (Swipe model + mutual-match detection) → replaces swipe/matches stubs.
- **Chat**: conversations + messages + WebSocket socket server → then flip `realtimeEnabled` on.
- **Translate** backend (`POST /translate`) — pick a provider (DeepL/Google/LLM).
- Stories: switch discovery/visibility to **matches-only** once matches exist (single swap point in `storyService.visibleAuthorFilter`).
- Replace placeholder **legal copy** in `LegalDocumentSheet` before launch.

---

## 11. Update log — 2026-07-26 (Honest-MVP hardening + Chat)

Specs/plans in `docs/superpowers/`. All changes reviewed + tested (frontend `flutter test`
green; backend `node --test` green). The user's unrelated in-progress files were preserved.

**Honest-MVP phases (frontend, on `feat/phase-a-visual-foundation`):**
- **Casing** — `User.fromJson` parses both camelCase (`/users/me`, `/auth/*`) and snake_case
  (`/discover`); `PATCH /users/me` sends camelCase. Profile fields/preferences no longer default.
- **Auth honest & safe** — removed the email-verify dead-end from registration; hid social login +
  forgot-password behind `EnvConfig.authSocialEnabled`/`forgotPasswordEnabled` (off); moved tokens to
  `flutter_secure_storage` (with migration); gated API logging behind `kDebugMode` (no token/PII in
  release logs). *(18+ age gate already satisfied by the registration slider `min:18`.)*
- **Profile photos** — wired real delete + set-as-main via an index-aligned `User.photoIds`.
- **Report/Block** — new `ReportBlockMenu` + `reportServiceProvider` on the profile detail screen
  (App-Store safety gate).
- **Account deletion** — wired the settings delete dialog to the real `deleteAccount` service
  (App-Store requirement) + logout/route-away.
- **Hide broken chat** — Phase 5 removed the Chat tab (now re-enabled behind a flag, see below).

**Chat (new, spans both repos):**
- **Backend** — on branch **`feat/flame-chat`** (NOT deployed; `main` auto-deploys, so it's isolated).
  `Conversation` + `Message` models + REST: `GET/POST /conversations`, `GET/POST
  /conversations/:id/messages`, `PUT /conversations/:id/read`, `POST/DELETE /messages/:id/reactions`,
  `reply_to` on send, and a lean embedded `other_user`. snake_case, String ids, offset pagination,
  participant-only authorization. Tests in `flame/__tests__/{chatModels,conversations,reactions}.test.js`.
- **Frontend** — `Message.fromJson` + `ChatService` reconciled to that contract (mock-tested); chat
  screen fixed (send-failure restore, newest-at-bottom ordering, offset paging, 4s polling);
  media/stickers/edit/delete/typing UI hidden (text-only MVP); Chat tab re-enabled behind
  **`EnvConfig.chatEnabled`** (true for `_local`, false for `_prod`).

**To go live with chat (deferred, deliberate):**
1. Merge `feat/flame-chat` → `main` (auto-deploys) → **`pm2 restart language`** (gotcha #1).
2. Flip `_prod.chatEnabled = true` in `lib/config/env.dart`.
3. Deferred features: Socket.IO realtime (replaces polling), media messages (needs the Spaces fix),
   the BananaTalk long-tail (edit/delete/pin/forward/polls/etc.).

**Known parked follow-ups:** backend unread-counter / find-or-create race (harden with `$inc`/unique
index); chat send-restore can clobber text typed during an in-flight send. Non-blocking.
