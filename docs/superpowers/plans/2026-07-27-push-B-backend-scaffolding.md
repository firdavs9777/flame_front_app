# Push Notifications (B) — Backend Scaffolding (infra-graceful)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Checkbox steps.

**Goal:** Build the flame backend for push notifications so it's fully wired and tested, but **degrades gracefully when Firebase isn't configured** (no service account / env). Device-token registration + notification settings + a guarded `pushService` + the chat-message trigger. The actual FCM delivery only happens once the user provides Firebase creds; until then it no-ops (logged). The Flutter `firebase_messaging` native integration is OUT OF SCOPE here (needs `google-services.json` etc.).

## Global Constraints
- Repo `/Users/firdavsmutalipov/Projects/BananaTalk/backend`, branch **`feat/flame-chat`** (never `main`). Re-check branch before each commit. ISOLATION unchanged (flame-only; the /flame socket stays isolated).
- Flame conventions: String ids; snake_case responses; `FlameError` family; models via `getConn().model`; zod routes; `node --test` (slow, don't background).
- `firebase-admin` is already a dependency of the shared backend (`require('firebase-admin')` works from `flame/`). Do NOT add creds or a service-account file to the repo.
- **Graceful gating:** push is "configured" only if `process.env.FLAME_FIREBASE_PROJECT_ID` (or a flame service-account path env) is set AND firebase-admin initializes without throwing. When not configured, every send is a logged no-op — NEVER throws into the caller. Tests run with NO creds → exercise the no-op + gating paths.
- Reference (read): BananaTalk `services/fcmService.js`, `services/notificationService.js`, `routes/notifications.js`, `models/User.js` (fcmTokens/notificationSettings) at `/Users/firdavsmutalipov/Projects/BananaTalk/backend`; flame patterns in `flame/services/chatService.js`, `flame/routes/*`, `flame/models/User.js`, `flame/socket/flameSocket.js`.

---

### Task 1: Device-token registration + notification settings (models + endpoints + tests)
**Files:** modify `flame/models/User.js` (add `fcmTokens` + `notificationSettings`); create `flame/services/deviceService.js`; create `flame/controllers/notificationController.js`; create `flame/routes/notifications.js`; register in `flame/index.js`; test `flame/__tests__/notifications.test.js`.
- `User.js`: add `fcmTokens: [{ token, platform, deviceId, lastUpdated, active }]` (default []) and `notificationSettings: { enabled:{type:Boolean,default:true}, chatMessages:{default:true}, matches:{default:true} }` (subdoc, sensible defaults).
- `deviceService.js`: `registerToken(userId, {token, platform, deviceId})` (upsert by deviceId — replace token, set active, lastUpdated=now); `removeToken(userId, deviceId)`; `getSettings(userId)`; `updateSettings(userId, patch)`. All via the User model. snake_case shapers.
- Endpoints under `/flamebackend/v1/notifications` (auth): `POST /register-token` (zod: token, platform enum ['ios','android'], deviceId), `DELETE /remove-token/:deviceId`, `GET /settings`, `PUT /settings` (zod: optional booleans).
- Register `router.use('/notifications', require('./routes/notifications'))` in `flame/index.js` (additive, before errorMiddleware).
- Tests (mirror conversations.test.js): register a token (persists on the user), register again same deviceId (replaces, no dup), remove token, get settings (defaults), update settings (persists), auth 401, validation 422.
- Commit `feat(flame): device-token registration + notification settings`.

### Task 2: pushService (guarded firebase-admin) + chat trigger + tests
**Files:** create `flame/services/pushService.js`; modify `flame/controllers/chatController.js` (trigger on send); test `flame/__tests__/pushService.test.js`.
- `pushService.js`:
  - `isConfigured()` — true iff `process.env.FLAME_FIREBASE_PROJECT_ID` set (and lazy `admin.initializeApp` with a flame service account succeeded). Cache the init result; wrap init in try/catch → configured=false on any failure. NEVER throw at require time.
  - `sendToUser(userId, {title, body, data})` — load the user; if `!isConfigured()` OR `notificationSettings.enabled===false` → log + return `{sent:0, skipped:true}` (no throw). Else gather active `fcmTokens`, `admin.messaging().sendEachForMulticast(...)`, prune tokens that come back `messaging/registration-token-not-registered`/`invalid-argument`, return `{sent:n}`.
  - `sendChatMessage(receiverId, {senderName, text, conversationId})` — respects `notificationSettings.chatMessages`; builds a chat payload; calls sendToUser.
- Chat trigger: in `chatController.sendMessage`, after the socket emit, add a guarded best-effort `pushService.sendChatMessage(data.receiver_id, {...})` (try/catch, never fail the REST send). (Model on BananaTalk emitting push off the message path.)
- Tests (`pushService.test.js`): with NO Firebase env → `isConfigured()` false; `sendToUser`/`sendChatMessage` return `{skipped:true}` and DON'T throw (this is the path that runs in CI). Settings gating: a user with `notificationSettings.enabled=false` (or chatMessages=false) is skipped even if configured were true — test the gating branch by stubbing `isConfigured` true + `admin` mocked, OR keep it to the unconfigured + settings-off paths which are deterministic without creds. Do NOT require real Firebase.
- Commit `feat(flame): guarded pushService + chat push trigger (no-op until Firebase configured)`.

### Task 3: Full flame suite verification
- `node --test flame/__tests__/*.test.js` green (or the chat+notifications+push subset if the full run is too slow); branch feat/flame-chat; clean tree.

## Deferred (needs the user's Firebase infra)
- Real FCM delivery (service-account JSON + `FLAME_FIREBASE_PROJECT_ID` on the server).
- Flutter `firebase_messaging` integration (google-services.json / GoogleService-Info.plist / APNs) — a separate frontend sub-project once creds exist.
- Match/other notification types beyond chat.

## Self-Review
Everything here runs + is tested WITHOUT Firebase (the no-op/gating paths are the CI paths); the real send is a guarded seam that activates when creds appear. Registration + settings are fully backed + tested. Isolation + flame conventions preserved. ✅
