# SP1 — Social Auth Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add Google/Apple/Facebook social sign-in + an email-availability check to the flame backend, matching the existing Flutter contract, fully isolated from BananaTalk/Fitbowl, and dormant (clean 501) until each provider's `FLAME_`-prefixed keys are set. Also fix the currently-broken email register contract (persist location + photos; require `lookingFor` camelCase).

**Architecture:** Controllers verify provider tokens via guarded verifiers (`google-auth-library` / `apple-signin-auth` / Facebook Graph over `axios`), then a pure `socialAuthService.findOrCreate` does find-by-provider-id → link-by-verified-email → create-new, and mints the standard flame token pair. All new files are flame-only; the only edits to existing flame files are additive routes, an additive controller export, a conditional `passwordHash` requirement, and an extended `registerSchema` + `authService.register`.

**Tech Stack:** Node/Express, Mongoose (flame connection), zod, `google-auth-library` + `apple-signin-auth` + `axios` (all already in the shared backend deps), `node --test` + mongodb-memory-server.

## Global Constraints
- Repo `/Users/firdavsmutalipov/Projects/BananaTalk/backend`. **Create and work on branch `feat/flame-social-auth`** off the current `feat/flame-chat` (so it includes the chat/notifications work). Never commit to `main`. Re-check branch before every commit.
- **ISOLATION (absolute):** touch only `flame/` files. Do NOT modify BananaTalk or Fitbowl auth, `controllers/auth.js`, passport strategies, shared `server.js`, or any non-flame file. All new provider env vars are `FLAME_`-prefixed. Verify `git diff --stat` shows only `flame/` paths before each commit.
- Flame conventions: String ids (`user._id.toString()`); the `/auth` router emits **camelCase** token keys (`accessToken`, `refreshToken`, `expiresIn`) — match `authService.mintTokenPair`; error classes `FlameError(code,msg,status=400)`, `AuthError(code,msg)`=401, `NotFoundError(msg)`=404, `ValidationError(msg)`=422, `ConflictError(code,msg)`=409 (NO ForbiddenError; use `new FlameError('FORBIDDEN', msg, 403)`); models via the flame connection already set up in `flame/models/User.js`; zod `validate.body(schema)` middleware; `asyncHandler` wraps controllers.
- Request bodies from the app are snake_case for social endpoints: `id_token`, `authorization_code`, `access_token`, `device_token`. Accept exactly those keys. `device_token` is accepted-but-ignored (parity with register/login, which also ignore it) — do NOT wire push here.
- Response envelope: `res.status(201|200).json({ success:true, data:{ user, tokens, is_new_user } })`. `user` = `authService.toPublic(user)`. `201` when a new user was created, `200` otherwise.
- "Configured" per provider: Google→`FLAME_GOOGLE_CLIENT_ID`; Apple→`FLAME_APPLE_CLIENT_ID`; Facebook→`FLAME_FACEBOOK_APP_ID` AND `FLAME_FACEBOOK_APP_SECRET`. Hitting an unconfigured provider → `throw new FlameError('PROVIDER_NOT_CONFIGURED', '<Provider> sign-in is not configured', 501)`. Verifiers NEVER throw at require time.
- Tests run with NO provider creds. The `findOrCreate` service is pure (takes an already-verified payload) so it is fully testable without creds; controller/route tests that need verification stub the verifier via `require.cache` replacement or by asserting the 501-unconfigured path.
- Test harness: copy `setupEnv()` (FLAME_JWT_* env + require.cache reset + `connect()`) and `dbHelper` usage from `flame/__tests__/authService.test.js`; for HTTP tests use `flame/__tests__/helpers/app.js` like `conversations.test.js`/`auth.test.js`. Run `node --test` (slow — do NOT background).

---

### Task 1: User model relaxation + register-contract fix (location + photos)

**Files:**
- Modify: `flame/models/User.js` (conditional `passwordHash`; add `profileComplete`)
- Modify: `flame/routes/auth.js` (extend `registerSchema`)
- Modify: `flame/services/authService.js` (persist location/photos in `register`)
- Test: `flame/__tests__/authService.test.js` (extend), `flame/__tests__/userModel.test.js` (extend)

**Interfaces:**
- Produces: `authService.register(input)` now accepts optional `latitude`, `longitude`, `photos`; persists `location.coordinates`, `locationGeo.coordinates=[lng,lat]`, `photos`. `User.passwordHash` no longer required for social users. `User.profileComplete` (Boolean).

- [ ] **Step 1: Relax `passwordHash` + add `profileComplete` in `flame/models/User.js`.**
  Change `passwordHash: { type: String, required: true }` to:
  ```js
  passwordHash: {
    type: String,
    required: function () { return !this.googleId && !this.appleId && !this.facebookId; },
    default: null,
  },
  ```
  Add near the social-auth fields:
  ```js
  profileComplete: { type: Boolean, default: true },
  ```

- [ ] **Step 2: Extend `registerSchema` in `flame/routes/auth.js`** (additive, all new fields optional):
  ```js
  const registerSchema = z.object({
    email:      z.string().email(),
    password:   z.string().min(8).max(128),
    name:       z.string().min(2).max(50),
    age:        z.number().int().min(18).max(100),
    gender:     z.enum(GENDERS),
    lookingFor: z.enum(GENDERS),
    bio:        z.string().max(500).optional(),
    interests:  z.array(z.string().min(1)).min(1).max(10),
    latitude:   z.number().min(-90).max(90).optional(),
    longitude:  z.number().min(-180).max(180).optional(),
    photos:     z.array(z.string().url()).max(9).optional(),
  });
  ```

- [ ] **Step 3: Persist location + photos in `authService.register`.** After building the base fields and before `User.create`, map optional location/photos. Replace the `User.create({...})` call so it includes:
  ```js
  const doc = {
    email: input.email.toLowerCase().trim(),
    passwordHash,
    name: input.name, age: input.age, gender: input.gender,
    lookingFor: input.lookingFor, interests: input.interests, bio: input.bio,
  };
  if (typeof input.latitude === 'number' && typeof input.longitude === 'number') {
    doc.location = { coordinates: { latitude: input.latitude, longitude: input.longitude } };
    doc.locationGeo = { type: 'Point', coordinates: [input.longitude, input.latitude] };
  }
  if (Array.isArray(input.photos) && input.photos.length) {
    doc.photos = input.photos.map((url, i) => ({
      id: `${Date.now()}_${i}`, url, isPrimary: i === 0, order: i,
    }));
  }
  user = await User.create(doc);
  ```
  Keep the existing `catch (e) { if (e.code === 11000) throw new ConflictError('EMAIL_TAKEN', ...) }` and the fire-and-forget welcome email exactly as-is.

- [ ] **Step 4: Tests.** In `authService.test.js` add: (a) register with `latitude`/`longitude`/`photos` persists `user` location + photos (fetch the User doc, assert `locationGeo.coordinates` = `[lng, lat]`, `location.coordinates.latitude`, `photos[0].isPrimary === true`); (b) register WITHOUT them still succeeds and leaves `location` null. In `userModel.test.js` add: a user with `googleId` set and no `passwordHash` validates/saves; a user with neither social id nor passwordHash fails validation.

- [ ] **Step 5: Run** `node --test flame/__tests__/authService.test.js flame/__tests__/userModel.test.js` → green.

- [ ] **Step 6: Commit** `fix(flame): register persists location + photos; passwordHash optional for social users`.

---

### Task 2: Guarded provider verifiers (`socialVerify`)

**Files:**
- Create: `flame/utils/socialVerify.js`
- Test: `flame/__tests__/socialVerify.test.js`

**Interfaces:**
- Produces:
  - `isConfigured(provider)` → boolean, `provider ∈ {'google','apple','facebook'}`.
  - `verifyGoogle(idToken)` → `Promise<{ providerId, email, name, emailVerified, photo }>`
  - `verifyApple(idToken)` → `Promise<{ providerId, email, name, emailVerified }>`
  - `verifyFacebook(accessToken)` → `Promise<{ providerId, email, name, emailVerified }>`
  - Each `verifyX` assumes configured; throws `new AuthError('INVALID_SOCIAL_TOKEN', '...')` on failure. Never throws at module load.

- [ ] **Step 1: Write `flame/utils/socialVerify.js`.**
  ```js
  const { AuthError } = require('./errors');

  function isConfigured(provider) {
    if (provider === 'google') return !!process.env.FLAME_GOOGLE_CLIENT_ID;
    if (provider === 'apple') return !!process.env.FLAME_APPLE_CLIENT_ID;
    if (provider === 'facebook')
      return !!(process.env.FLAME_FACEBOOK_APP_ID && process.env.FLAME_FACEBOOK_APP_SECRET);
    return false;
  }

  async function verifyGoogle(idToken) {
    try {
      const { OAuth2Client } = require('google-auth-library');
      const client = new OAuth2Client(process.env.FLAME_GOOGLE_CLIENT_ID);
      const ticket = await client.verifyIdToken({
        idToken, audience: process.env.FLAME_GOOGLE_CLIENT_ID,
      });
      const p = ticket.getPayload();
      if (!p || !p.sub) throw new Error('no payload');
      return {
        providerId: p.sub, email: p.email || null, name: p.name || null,
        emailVerified: p.email_verified === true, photo: p.picture || null,
      };
    } catch (_e) {
      throw new AuthError('INVALID_SOCIAL_TOKEN', 'Invalid Google token');
    }
  }

  async function verifyApple(idToken) {
    try {
      const appleSignin = require('apple-signin-auth');
      const p = await appleSignin.verifyIdToken(idToken, {
        audience: process.env.FLAME_APPLE_CLIENT_ID,
        ignoreExpiration: false,
      });
      if (!p || !p.sub) throw new Error('no payload');
      return {
        providerId: p.sub, email: p.email || null, name: null,
        emailVerified: p.email_verified === 'true' || p.email_verified === true,
      };
    } catch (_e) {
      throw new AuthError('INVALID_SOCIAL_TOKEN', 'Invalid Apple token');
    }
  }

  async function verifyFacebook(accessToken) {
    try {
      const axios = require('axios');
      const appToken = `${process.env.FLAME_FACEBOOK_APP_ID}|${process.env.FLAME_FACEBOOK_APP_SECRET}`;
      const debug = await axios.get('https://graph.facebook.com/debug_token', {
        params: { input_token: accessToken, access_token: appToken },
      });
      const d = debug.data && debug.data.data;
      if (!d || d.is_valid !== true || d.app_id !== process.env.FLAME_FACEBOOK_APP_ID) {
        throw new Error('invalid token');
      }
      const me = await axios.get('https://graph.facebook.com/me', {
        params: { fields: 'id,name,email', access_token: accessToken },
      });
      const m = me.data;
      if (!m || !m.id) throw new Error('no profile');
      return {
        providerId: m.id, email: m.email || null, name: m.name || null,
        emailVerified: !!m.email, // FB only returns verified emails
      };
    } catch (_e) {
      throw new AuthError('INVALID_SOCIAL_TOKEN', 'Invalid Facebook token');
    }
  }

  module.exports = { isConfigured, verifyGoogle, verifyApple, verifyFacebook };
  ```

- [ ] **Step 2: Tests (`socialVerify.test.js`, no creds).**
  - `isConfigured('google'|'apple'|'facebook')` all false when the relevant env vars are unset (delete them at test start); true when set (set dummy values, assert true, then restore).
  - `verifyGoogle('garbage')` rejects with an `AuthError` (code `INVALID_SOCIAL_TOKEN`) and does not crash the process (set `FLAME_GOOGLE_CLIENT_ID='x'` so it reaches the try/catch).
  - `verifyFacebook('garbage')` rejects with `AuthError` (set the two FB env vars to dummy; the axios call will fail/return invalid → caught). Use a short assertion; do NOT hit the real network deliberately — a rejected/failed axios call still lands in the catch and yields the AuthError, which is what we assert.
  - Do NOT require real provider verification to pass.

- [ ] **Step 3: Run** `node --test flame/__tests__/socialVerify.test.js` → green.
- [ ] **Step 4: Commit** `feat(flame): guarded social token verifiers (google/apple/facebook)`.

---

### Task 3: `socialAuthService.findOrCreate` (find → link → create)

**Files:**
- Create: `flame/services/socialAuthService.js`
- Test: `flame/__tests__/socialAuthService.test.js`

**Interfaces:**
- Consumes: `authService.mintTokenPair`, `authService.toPublic`; the `User` model.
- Produces: `findOrCreate(provider, payload)` where `provider ∈ {'google','apple','facebook'}` and `payload = { providerId, email, name, emailVerified, photo? }`. Returns `Promise<{ user:<toPublic>, tokens, isNew:boolean }>`.

- [ ] **Step 1: Write `flame/services/socialAuthService.js`.**
  ```js
  const User = require('../models/User');
  const authService = require('./authService');

  const ID_FIELD = { google: 'googleId', apple: 'appleId', facebook: 'facebookId' };

  async function findOrCreate(provider, payload) {
    const idField = ID_FIELD[provider];
    if (!idField) throw new Error(`unknown provider ${provider}`);
    const { providerId, email, name, emailVerified, photo } = payload;

    // 1. Existing account with this provider id → login.
    let user = await User.findOne({ [idField]: providerId, isDeleted: { $ne: true } });
    let isNew = false;

    // 2. Else link to an existing account by VERIFIED email.
    if (!user && email && emailVerified) {
      user = await User.findOne({ email: email.toLowerCase().trim(), isDeleted: { $ne: true } });
      if (user) { user[idField] = providerId; }
    }

    // 3. Else create a new (incomplete) social user.
    if (!user) {
      user = new User({
        email: email ? email.toLowerCase().trim() : `${provider}_${providerId}@social.flame`,
        name: name || 'New User',
        [idField]: providerId,
        profileComplete: false,
        // dating fields (age/gender/lookingFor/interests) collected by the
        // frontend social-profile-completion flow after first login.
        age: 18, gender: 'other', lookingFor: 'other', interests: [],
        photos: photo ? [{ id: `${provider}_0`, url: photo, isPrimary: true, order: 0 }] : [],
      });
      isNew = true;
    }

    user.lastActive = new Date();
    user.isOnline = true;
    await user.save();

    const tokens = await authService.mintTokenPair(user);
    return { user: authService.toPublic(user), tokens, isNew };
  }

  module.exports = { findOrCreate };
  ```
  Note on the synthetic email: only used when the provider returns no email (rare; e.g. Apple relay declined). It keeps the `unique` email index satisfied. Age/gender defaults keep the required-enum validators happy until the completion flow overwrites them; `profileComplete=false` marks them provisional.

- [ ] **Step 2: Tests (`socialAuthService.test.js`, uses db harness, no creds).**
  - New provider id, no existing email → creates a user with `isNew===true`, `profileComplete===false`, `googleId===providerId`, and returns camelCase `tokens.accessToken`/`tokens.refreshToken`.
  - Same provider id again → `isNew===false`, same user `id`.
  - New provider id but `email` matches an existing password user AND `emailVerified===true` → links (`isNew===false`, existing user now has `googleId` set, still has its `passwordHash`).
  - Email matches existing user but `emailVerified===false` → does NOT link; creates a new user (`isNew===true`).
  - `facebook`/`apple` id fields set correctly (spot-check one other provider).

- [ ] **Step 3: Run** `node --test flame/__tests__/socialAuthService.test.js` → green.
- [ ] **Step 4: Commit** `feat(flame): social find-or-create with verified-email account linking`.

---

### Task 4: Controllers + routes (`/auth/google|apple|facebook`, `/auth/check-email`)

**Files:**
- Create: `flame/controllers/socialAuthController.js`
- Modify: `flame/routes/auth.js` (add schemas + routes)
- Test: `flame/__tests__/socialAuth.test.js` (HTTP, via `helpers/app.js`)

**Interfaces:**
- Consumes: `socialVerify`, `socialAuthService.findOrCreate`, `User` (for check-email).

- [ ] **Step 1: Write `flame/controllers/socialAuthController.js`.**
  ```js
  const { FlameError, ValidationError } = require('../utils/errors');
  const socialVerify = require('../utils/socialVerify');
  const socialAuthService = require('../services/socialAuthService');
  const User = require('../models/User');

  function guard(provider) {
    if (!socialVerify.isConfigured(provider)) {
      const label = { google: 'Google', apple: 'Apple', facebook: 'Facebook' }[provider];
      throw new FlameError('PROVIDER_NOT_CONFIGURED', `${label} sign-in is not configured`, 501);
    }
  }

  async function respond(res, provider, payload) {
    const { user, tokens, isNew } = await socialAuthService.findOrCreate(provider, payload);
    res.status(isNew ? 201 : 200).json({
      success: true, data: { user, tokens, is_new_user: isNew },
    });
  }

  async function google(req, res) {
    guard('google');
    const payload = await socialVerify.verifyGoogle(req.body.id_token);
    await respond(res, 'google', payload);
  }

  async function apple(req, res) {
    guard('apple');
    const payload = await socialVerify.verifyApple(req.body.id_token);
    await respond(res, 'apple', payload);
  }

  async function facebook(req, res) {
    guard('facebook');
    const payload = await socialVerify.verifyFacebook(req.body.access_token);
    await respond(res, 'facebook', payload);
  }

  async function checkEmail(req, res) {
    const email = String(req.body.email || '').toLowerCase().trim();
    const exists = await User.exists({ email, isDeleted: { $ne: true } });
    res.json({ success: true, data: { available: !exists } });
  }

  module.exports = { google, apple, facebook, checkEmail };
  ```

- [ ] **Step 2: Add schemas + routes in `flame/routes/auth.js`** (additive; require the new controller as `social`):
  ```js
  const social = require('../controllers/socialAuthController');

  const googleSchema   = z.object({ id_token: z.string().min(1), device_token: z.string().optional() });
  const appleSchema    = z.object({ id_token: z.string().min(1), authorization_code: z.string().optional(), device_token: z.string().optional() });
  const facebookSchema = z.object({ access_token: z.string().min(1), device_token: z.string().optional() });
  const checkEmailSchema = z.object({ email: z.string().email() });

  router.post('/google',      validate.body(googleSchema),   asyncHandler(social.google));
  router.post('/apple',       validate.body(appleSchema),    asyncHandler(social.apple));
  router.post('/facebook',    validate.body(facebookSchema), asyncHandler(social.facebook));
  router.post('/check-email', validate.body(checkEmailSchema), asyncHandler(social.checkEmail));
  ```

- [ ] **Step 3: Tests (`socialAuth.test.js`, HTTP via supertest/`helpers/app.js`).**
  - `POST /auth/check-email` with a fresh email → `200 { data:{ available:true } }`; register a user, then check-email that email → `available:false`; invalid email → `422`.
  - With NO provider env set: `POST /auth/google {id_token:'x'}` → `501` with code `PROVIDER_NOT_CONFIGURED`; same for `/auth/apple`, `/auth/facebook`.
  - Configured-but-verification path: set `FLAME_GOOGLE_CLIENT_ID`, then stub the verifier by replacing `require.cache[require.resolve('../utils/socialVerify')].exports.verifyGoogle` with a fn returning a fixed payload `{providerId:'g1', email:'g@x.com', name:'Gee', emailVerified:true}` (do the stub BEFORE the app requires the controller, or reset the controller's cache too — follow the require.cache reset pattern from `authService.test.js`). Assert `POST /auth/google` → `201 { data:{ user, tokens:{accessToken,refreshToken}, is_new_user:true } }`; a second call → `200 is_new_user:false`.
  - (If stubbing through the HTTP layer proves brittle, it is acceptable to assert the 501/unconfigured + check-email paths over HTTP and rely on Task 3's service tests for find-or-create — but attempt the stub first.)

- [ ] **Step 4: Run** `node --test flame/__tests__/socialAuth.test.js` → green.
- [ ] **Step 5: Commit** `feat(flame): social auth endpoints + email-availability check`.

---

### Task 5: env docs + full-suite verification

**Files:**
- Modify: `flame/config/flame.env.example`

- [ ] **Step 1: Append the social-auth env block** to `flame/config/flame.env.example`:
  ```
  # --- Social sign-in (each provider is dormant until its keys are set) ---
  # Google: the OAuth **Web** client ID (must equal the serverClientId the app mints tokens for)
  FLAME_GOOGLE_CLIENT_ID=
  # Apple: the Services ID / bundle audience the ID token is issued for
  FLAME_APPLE_CLIENT_ID=
  # Facebook: app id + secret (used to build the app access token for debug_token)
  FLAME_FACEBOOK_APP_ID=
  FLAME_FACEBOOK_APP_SECRET=
  ```

- [ ] **Step 2: Run the auth-related suite** `node --test flame/__tests__/authService.test.js flame/__tests__/auth.test.js flame/__tests__/socialVerify.test.js flame/__tests__/socialAuthService.test.js flame/__tests__/socialAuth.test.js flame/__tests__/userModel.test.js` → all green.
- [ ] **Step 3:** Verify `git diff --stat main...feat/flame-social-auth` (or against `feat/flame-chat`) shows ONLY `flame/` paths. Clean tree.
- [ ] **Step 4: Commit** `docs(flame): document social-auth env vars`.

## Deferred (needs the user's provider infra)
- Real verification requires: `FLAME_GOOGLE_CLIENT_ID` (already have the value hardcoded in the app), an Apple Services ID + key, and a Facebook app id/secret + the app configured for Login.
- Native app config for Apple (Sign in with Apple capability/entitlement) and Facebook (URL scheme, `Info.plist`) — frontend/native, tracked in SP2 + the activation runbook.
- Wiring `device_token` into push registration on social login (currently accepted-but-ignored, matching register/login).

## Self-Review
Every task runs + is tested WITHOUT provider creds (the 501 path, the pure find-or-create, and the failed-verify path are the CI paths). Real verification is a guarded seam. `findOrCreate` is a pure function of an already-verified payload, so it needs no mocking framework. Isolation preserved (flame-only files + additive edits). Register-contract fix is backward-compatible (new fields optional). ✅
