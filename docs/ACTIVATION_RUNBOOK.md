# Flame — Activation Runbook (add keys later, it just works)

The chat/realtime/push/email backend is fully built and **dormant-safe**: every provider
integration no-ops until its FLAME-specific keys are present, then activates automatically. This
runbook is the checklist to turn each piece on when you have the credentials. Nothing here needs code
changes — it's config + a small one-time Flutter native step for push.

> Backend lives on branch **`feat/flame-chat`** (chat + realtime + push + email) and
> **`feat/flame-ops-hardening`** (DB-connect resilience + Spaces diagnostics), repo
> `~/Projects/BananaTalk/backend`. All flame env vars are documented in
> `flame/config/flame.env.example`.

---

## 0. Deploy the backend (do this first)

1. Merge `feat/flame-chat` and `feat/flame-ops-hardening` → `main` (auto-deploys).
2. **`pm2 restart language`** (the deploy→DB-disconnect gotcha; the ops branch mitigates it but restart to be safe).
3. Verify: `GET https://api.banatalk.com/flamebackend/v1/health` → `dbStatus: connected`.

All the flame integrations below read from the server's env (`config/config.env` on the box). They
stay inert until their keys are set, so deploying is safe even before you add any keys.

---

## 1. Email (Mailgun) — auto-activates on env

**You provide:** a Mailgun account + a verified sending domain (add Mailgun's SPF/DKIM DNS records).

**Then set on the server** (`config/config.env`), from `flame/config/flame.env.example`:
```
FLAME_MAILGUN_API_KEY=<your mailgun key>
FLAME_MAILGUN_DOMAIN=<your verified domain, e.g. mg.flame.app>
FLAME_MAILGUN_REGION=us            # or 'eu'
FLAME_FROM_EMAIL=noreply@flame.app
FLAME_FROM_NAME=Flame
```
`pm2 restart language`. That's it — no code change:
- `flame/utils/sendEmail.js` `isConfigured()` flips true → the welcome email on registration
  (`authService.register`) starts sending.
- `startEmailScheduler()` (already wired into `server.js`, guarded) begins scheduling its jobs.
- **Isolation note:** these are FLAME-prefixed on purpose — flame will NOT piggyback on BananaTalk's
  shared `MAILGUN_*`. If you want flame to use the same Mailgun account, set the FLAME_ vars to the
  same values.

**Verify:** register a new flame user → a welcome email arrives; check `pm2 logs language | grep -i email`.

---

## 2. Push (Firebase/FCM) — backend auto-activates on env

**You provide:** a Firebase project (its own, isolated from BananaTalk) → a **service-account JSON**,
and (for iOS) an **APNs auth key** uploaded to that Firebase project.

**Then set on the server:**
```
FLAME_FIREBASE_PROJECT_ID=<your firebase project id>
FLAME_FIREBASE_SERVICE_ACCOUNT=/absolute/path/to/flame-service-account.json
```
Drop the JSON at that path. `pm2 restart language`. No code change:
- `flame/services/pushService.js` initializes a **named `'flame'`** firebase-admin app (isolated from
  BananaTalk's default app) and `isConfigured()` flips true → chat messages push to the receiver
  (wired in `chatController.sendMessage`), gated by each user's `notificationSettings`.
- Device tokens are already accepted at `POST /flamebackend/v1/notifications/register-token`.

**Verify:** once the app registers a token (step 3), send a message to that user from another account
→ a push arrives; `pm2 logs language | grep -i push`.

---

## 3. Push (Flutter app) — the one manual native step

This is the only part that needs a code/config change in the app, because the native build tooling
requires the Firebase config files (which is why it wasn't pre-added — it would break the build).

1. From your Firebase project, add the config files:
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`
   (Easiest: run `flutterfire configure` — it generates `lib/firebase_options.dart` + places these.)
2. Add deps: `flutter pub add firebase_core firebase_messaging flutter_local_notifications`.
3. Android: apply the Google-services Gradle plugin (`android/build.gradle` classpath +
   `android/app/build.gradle` `apply plugin: 'com.google.gms.google-services'`). iOS: ensure the APNs
   key is on the Firebase project + Push Notifications capability is enabled in Xcode.
4. Add the service below and call `FlamePushService().init(ref)` after login (e.g. in `main_shell`),
   and flip a flag so it's only active where you want it. It registers the token with the backend
   endpoint that already exists.

**Paste-ready starting point — `lib/services/flame_push_service.dart`:**
```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/firebase_options.dart'; // from flutterfire configure

class FlamePushService {
  final _api = ApiClient();

  Future<void> init() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(); // iOS prompt
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await messaging.getToken();
    if (token != null) await _registerToken(token);
    messaging.onTokenRefresh.listen(_registerToken);

    FirebaseMessaging.onMessage.listen((m) {/* show a local notification */});
  }

  Future<void> _registerToken(String token) => _api.post(
        '/notifications/register-token',
        body: {
          'token': token,
          'platform': /* Platform.isIOS ? 'ios' : 'android' */ 'android',
          'device_id': token.substring(0, 16),
        },
      );
}
```
5. Also add a background handler (`FirebaseMessaging.onBackgroundMessage` with a top-level
   `@pragma('vm:entry-point')` function) per the firebase_messaging docs. Model the whole thing on
   BananaTalk's `lib/services/notification_service.dart` if you want tap-routing + local notifications.

**Verify:** log in → the app posts a token → `GET /flamebackend/v1/notifications/settings` shows the
user; a message from another account produces a push.

---

## 3b. Social sign-in (Google / Apple / Facebook) — backend auto-activates on env

> Backend lives on branch **`feat/flame-social-auth`** (off `feat/flame-chat`). Deploying it also
> **repairs email registration** (previously 422'd + dropped location/photos) — that part needs NO keys.

The endpoints (`/auth/google`, `/auth/apple`, `/auth/facebook`) + `/auth/check-email` and the whole
app-side flow are built + tested. Each provider is dormant (returns a clean `501
PROVIDER_NOT_CONFIGURED`) until its keys are set.

**You provide + set on the server** (`config/config.env`, all `FLAME_`-prefixed so flame stays
isolated from BananaTalk's own Google/FB config):
```
# Google — the OAuth **Web** client ID (must equal the serverClientId the app mints tokens for;
# a Flame client ID is already hardcoded in the app's social_auth_service.dart — use that value)
FLAME_GOOGLE_CLIENT_ID=<web client id>
# Apple — the Services ID / bundle audience the ID token is issued for
FLAME_APPLE_CLIENT_ID=<services id>
# Facebook — app id + secret (used to build the app access token for debug_token verification)
FLAME_FACEBOOK_APP_ID=<app id>
FLAME_FACEBOOK_APP_SECRET=<app secret>
```
`pm2 restart language`. No code change — `socialVerify.isConfigured(...)` flips true per provider.

**App native config** (needed before the buttons work on device):
- **Apple:** enable *Sign in with Apple* capability + entitlement in Xcode. **Required by the App
  Store** if you offer any social login on iOS (guideline 4.8).
- **Facebook:** add the FB app id + URL scheme to `ios/Runner/Info.plist` + the Android manifest.
- **Google:** reuse the existing client config (already wired in the app).

**Then flip** `authSocialEnabled: true` in `lib/config/env.dart` `_prod` (see §4) — that reveals the
Google/Apple/Facebook buttons on welcome/login. Behavior: new social users are created
`profileComplete:false` and routed through the existing profile-completion flow; an existing email
signing in via a provider **links** (verified email only) rather than duplicating.

**Verify:** unconfigured provider → `POST /auth/google` returns `501`; once configured, a real sign-in
returns `{data:{user, tokens, is_new_user}}`; `pm2 logs language | grep -i social`.

---

## 4. Flip the go-live flags (app)

In `lib/config/env.dart` `_prod`, once the backend is deployed:
- `chatEnabled: true` — shows the Chat tab in prod.
- `realtimeEnabled: true` — connects the `/flame` socket in prod (turns polling into a fallback).
- `authSocialEnabled: true` — shows Google/Apple/Facebook buttons (only after §3b keys + native config).
- (optional) `advancedFiltersEnabled: true` — only once `/discover` honors gender/interests/online filters.
- (optional) `forgotPasswordEnabled` — only once that backend exists.

---

## 5. Still outstanding (not key-related)

- **DigitalOcean Spaces** env fix (`SPACES_ENDPOINT`/`DO_SPACES_KEY`/`DO_SPACES_SECRET`/
  `FLAME_SPACES_BUCKET`) — unblocks profile/story photo upload and chat media. The upload error is now
  logged with the real S3 code (`pm2 logs language | grep Spaces`) to pinpoint the misconfig.
- **Legal copy** — replace the placeholder ToS/Privacy in `legal_document_sheet.dart` with
  counsel-approved text before store submission.
- **Media messages** in chat — deferred until Spaces works; then it's an additive frontend+backend piece.

---

## Summary: what activates with just env (no code change)

| Feature | Activation |
|---|---|
| Email registration fix | deploy `feat/flame-social-auth` → `pm2 restart language` (**no keys needed**) |
| Email (welcome + scheduler) | set `FLAME_MAILGUN_*` + `FLAME_FROM_*` → restart |
| Push backend (chat → FCM) | set `FLAME_FIREBASE_PROJECT_ID` + `FLAME_FIREBASE_SERVICE_ACCOUNT` + drop JSON → restart |
| Social sign-in (backend) | set `FLAME_GOOGLE_CLIENT_ID` / `FLAME_APPLE_CLIENT_ID` / `FLAME_FACEBOOK_APP_ID`+`_SECRET` → restart (§3b) |
| Social sign-in (app) | Apple/Facebook native config + flip `authSocialEnabled` in `env.dart` |
| Chat/realtime in prod | flip `chatEnabled`/`realtimeEnabled` in `env.dart` |
| Push in the app | the one-time Flutter native step (§3) |
