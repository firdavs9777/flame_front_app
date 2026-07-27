# Social Auth + Registration/Auth-UX Optimization — Design

_Date: 2026-07-27 · Scope: honest-MVP, both backend and frontend · Isolation: flame-only, zero effect on BananaTalk/Fitbowl_

## Problem

The Flutter app already has a **complete social-login frontend** — `SocialAuthService`
(Google/Apple/Facebook SDKs), `authService.googleSignIn/appleSignIn/facebookSignIn`
(`POST /auth/{google,apple,facebook}`), `authProvider.socialLogin(...)`, and a
`social_profile_completion_flow.dart` — but it is gated off (`authSocialEnabled: false`)
because **the flame backend has no social endpoints** (only `/register /login /refresh
/logout`). The calls would 404. Separately, the email registration flow works but is
un-optimized: it only calls `register()` at the very end (after photos + location), uploads
photos serially, keeps no draft, forces every step, and the login/register/welcome UIs
predate the Phase-A design system.

The user asked to (1) make Google + Facebook + **Apple** login actually work, and
(2) fix + optimize the registration process and the login/register page UIs "properly".

## Decomposition

Two independent sub-projects, each its own spec-slice → plan → SDD build:

- **SP1 — Social Auth Backend** (`~/Projects/BananaTalk/backend`, branch
  `feat/flame-social-auth`). The gating dependency: the frontend can't be turned on until
  these endpoints exist. Infra-graceful (dormant until `FLAME_`-prefixed provider keys are
  present), fully isolated, tested.
- **SP2 — Registration + Auth-UX Optimization** (this repo, branch
  `feat/phase-a-visual-foundation`). Frontend only. Depends on SP1 for one new endpoint
  (email availability) and for the social flow being real, but the UX/UI work is independent
  and can land behind flags.

---

## SP1 — Social Auth Backend

### Contract (must match the existing frontend exactly)
- `POST /auth/google`   body `{ id_token, device_token? }`
- `POST /auth/apple`    body `{ id_token, authorization_code, device_token? }`
- `POST /auth/facebook` body `{ access_token, device_token? }`
- All return `201` (new user) / `200` (existing) with the **same envelope as `/register`**:
  `{ success:true, data:{ user:<toPublic>, tokens:{ access_token, refresh_token }, is_new_user:bool } }`.
- Also `POST /auth/check-email` body `{ email }` → `{ success:true, data:{ available:bool } }`
  (backs SP2 fail-fast validation; no auth required; format-validated by zod).

### Token verification (model on BananaTalk `controllers/auth.js`)
- **Google:** `new OAuth2Client(FLAME_GOOGLE_CLIENT_ID).verifyIdToken({ idToken, audience })`
  → `payload.sub` (googleId), `payload.email`, `payload.name`, `payload.picture`.
- **Apple:** `appleSignin.verifyIdToken(id_token, { audience: FLAME_APPLE_CLIENT_ID })`
  → `payload.sub` (appleId), `payload.email` (only on first consent).
- **Facebook:** Graph API — verify the token via
  `GET https://graph.facebook.com/debug_token?input_token=<t>&access_token=<FB_APP_ID>|<FB_APP_SECRET>`,
  then `GET /me?fields=id,name,email&access_token=<t>` → facebookId, email, name.
  (Uses the shared `axios`; no new dep.)

### Account model + linking (flame `User.js`)
- The `googleId / appleId / facebookId` sparse fields **already exist** — reuse them.
- **Relax `passwordHash`:** change `required:true` → required only when the user has no
  social id (`required: function(){ return !this.googleId && !this.appleId && !this.facebookId; }`).
  Existing password users are unaffected.
- **find-or-create + link** in a new `flame/services/socialAuthService.js`:
  1. Match by provider id → login. 2. Else match by verified email → **link** the provider id
  to that account (prevents duplicate accounts), then login. 3. Else create a new social user
  with the profile fields the provider gave us and `is_new_user:true`. New social users may be
  missing dating fields (age/gender/lookingFor/interests) — that's expected; the frontend's
  `social_profile_completion_flow` collects them. So social-created users are allowed to have
  those fields null/pending (schema already tolerates via the completion flow updating them).
     - **Decision:** create the user with a `profileComplete:false` marker; the completion flow
       (existing frontend) fills the rest via the existing profile-update endpoint.

### Infra-graceful gating (matches push/email pattern)
- A provider is "configured" iff its env is set: Google→`FLAME_GOOGLE_CLIENT_ID`,
  Apple→`FLAME_APPLE_CLIENT_ID`, Facebook→`FLAME_FACEBOOK_APP_ID`+`FLAME_FACEBOOK_APP_SECRET`.
- If a provider's endpoint is hit while unconfigured → `501` `FlameError('PROVIDER_NOT_CONFIGURED', ...)`
  (clean, logged, never crashes). `check-email` is always available.
- Documented in `flame/config/flame.env.example`. `authSocialEnabled` stays `false` in the app
  until the user confirms keys are live.

### Isolation & testing
- New flame-only files: `flame/services/socialAuthService.js`, `flame/controllers/socialAuthController.js`,
  additive routes in `flame/routes/auth.js`, `flame/utils/socialVerify.js` (the three verifiers,
  each guarded). No shared-file edits beyond the additive route lines and the `passwordHash`
  relax in flame's own `User.js`. No touch to BananaTalk/Fitbowl auth.
- Tests (`node --test`, mongodb-memory-server, no real provider creds): unconfigured→501;
  find-or-create (stub the verifier to return a fixed payload); email-linking; check-email
  available/taken; existing password-login unaffected.

---

## SP2 — Registration + Auth-UX Optimization (frontend)

Ordered by UX impact; each independently testable and flag-safe.

1. **Fail-fast validation (step 1).** On "next" from `StepEmailPassword`, validate email
   format + password rules inline, and call `POST /auth/check-email`; block advance with a
   clear inline error if taken. Debounced, with graceful fallback if the endpoint is
   unavailable (don't hard-block on network error — validate at final submit as today).
2. **Parallel + resilient photo upload.** Replace the serial `for` loop in
   `_uploadPhotosForRegistration` with `Future.wait` (bounded), per-photo retry (1 retry),
   preserving order + primary-first. Surface partial-failure clearly.
3. **Draft persistence / resume.** Persist `RegistrationData` (minus raw `File`s — persist
   photo file paths) to `shared_preferences` on each step; offer "Resume signup?" on return;
   clear on success or explicit cancel.
4. **Skippable steps.** Make bio/interests skippable (interests currently backend-min-1 — keep
   ≥1 required only if backend demands; otherwise allow skip and default). Add a "Skip for now"
   affordance where safe; ensure required dating fields still collected.
5. **UI polish (welcome / login / register).** Bring these onto the Phase-A design system
   (`widgets/kit`, `AppTheme` tokens): consistent inputs, buttons, spacing, error states,
   loading; real social buttons (Google/Apple/Facebook) shown only when `authSocialEnabled`;
   Apple button per Apple's HIG (black/white, correct label). Keep the existing gradient brand
   feel but standardized. No behavior regressions; keep animations tasteful.

### Flags
- Social buttons render only when `EnvConfig.authSocialEnabled`. Ship SP2 with the flag still
  `false`; flip to `true` in `_prod` only after SP1 is deployed and keys are set.

### Testing (frontend)
- `check-email` service + provider (MockClient, snake read); fail-fast step logic (widget/unit);
  parallel-upload helper (order + partial failure); draft persist/restore (unit);
  skippable-step logic; UI smoke widget tests for the three screens.

---

## Non-goals / deferred
- Real provider delivery (needs the user's Google/Apple/Facebook app credentials + native config
  — Apple entitlement, Facebook app + URL scheme; Google client already partly set). Documented
  in the activation runbook.
- Passwordless/magic-link, phone auth, account-merge UI conflict resolution.
- Backend rate-limiting specifics beyond what flame auth already applies.

## Isolation guarantee
Every SP1 change is a flame-only file or an additive line; verifier libs are already shared deps;
provider config is `FLAME_`-prefixed; nothing alters BananaTalk/Fitbowl auth, sessions, or the
default passport strategies. Verified the same way as the chat/push/email work.
