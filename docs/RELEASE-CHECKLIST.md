# Flame — what is left before release

Written 2026-08-23, after Chat Phase 1, Scope A (Discover), Scope B (Profile /
Settings / navigation), the Stories fix, the navigation route table, and Scope C2
(email) all shipped to `main` and deployed.

Everything below is either **someone's hands** or **an explicit decision**. None
of it is blocked on more code being written, except where noted.

---

## 1. Android keystore — blocks upload entirely

Release builds signed with the SDK's shared debug keystore (password `android`,
alias `androiddebugkey`) are rejected by Play outright. The config now reads
`android/key.properties`, and `bundleRelease` / `assembleRelease` **fail** without
it rather than emitting an artifact that dies at the Console.

```bash
export JAVA_HOME=/opt/homebrew/opt/openjdk@17   # default JDK 25 breaks Gradle 8.14
keytool -genkey -v -keystore ~/flame-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp android/key.properties.example android/key.properties
# fill storeFile / storePassword / keyAlias / keyPassword
```

Back up the `.jks` **and** the passwords somewhere you will still have in two
years. With Play App Signing a lost upload key can be reset by Google, but only
after a support round-trip during which nothing ships.

## 2. Mailgun — all of Scope C2 is inert without it

flame needs its **own** key and domain. It must never use BananaTalk's
`MAILGUN_API_KEY`; see the note in `flame/config/flame.env.example`.

```
FLAME_MAILGUN_API_KEY=
FLAME_MAILGUN_DOMAIN=
FLAME_FROM_EMAIL=
FLAME_FROM_NAME=Flame
FLAME_UNSUBSCRIBE_SECRET=      # 32+ chars, else links sign with the JWT secret
FLAME_PUBLIC_URL=              # optional, defaults to the api.banatalk.com path
```

Plus SPF and DKIM records on that domain, or everything lands in spam.

**Send transactional first.** A brand-new domain has no reputation; a burst of
marketing from one is the fastest way to get permanently spam-foldered. The
re-engagement ladder is throttled (50 per batch, 1s gap) for the same reason.

## 3. iOS Sign in with Apple — blocks App Store review

`googleSignInEnabled: true` with `appleSignInEnabled: false` and no entitlement
violates guideline 4.8. Rejected in review, not at upload. Needs the certificate
and entitlement from your Apple Developer account — the same account work as the
APNs key in item 5, so do them together.

## 4. Rotate two leaked credentials

- the MongoDB connection string, which contains its password
- the Google OAuth client secret

## 5. Firebase — only when you want push (Scope C1)

Project, `google-services.json` (Android), `GoogleService-Info.plist` + APNs key
(iOS), and `FLAME_FIREBASE_PROJECT_ID` on the droplet. `pushService` no-ops
safely without it, so skipping this is safe.

The app half is unbuilt: `firebase_messaging` is not a dependency, and nothing
requests permission, retrieves a token, or handles a message. The seam is ready
— `auth_service` already accepts a `deviceToken` and sends `device_token` on
login, register and both social paths, and the tap-to-conversation path exists
(`appNavigatorKey`, `AppRoutes.chat`, `ChatRouteArgs.id`, and
`GET /conversations/:id` to resolve an id from a payload).

## 6. AAB size

66.3MB, mostly `google_mlkit_face_detection`. Real engineering rather than a
config flip: deferring it or making it a download-on-demand module.

---

## Decisions, not tasks

### Password self-service does not exist

The app calls `/auth/forgot-password`, `/auth/reset-password` and
`/auth/change-password`. **None of the three exist server-side.** The UI is
correctly gated behind `forgotPasswordEnabled` (false in both presets) with a
comment in `settings_screen.dart` saying exactly that, so there is no dead
button — but nobody can change their password.

`emailService.sendPasswordChanged` and its template are written and tested, and
have no caller, because there is nothing to call them. Shipping a dating app
where a password cannot be changed is a real gap; adding an authenticated
password-change endpoint is an auth feature that deserves its own decision rather
than being folded into an email task.

### Promotional email will reach nobody, correctly

`notificationSettings.promotions` defaults to `false` and the Settings switch is
the only way in. That is the legally correct default — marketing is opt-in. For
actual reach you need a consent prompt during onboarding, which is a product
decision, not a missing implementation.

### The tab bar and IA are settled

Three tabs, Settings behind the gear in Profile, and the Chat tab keeps stories,
new matches and conversations in one scroll — decided explicitly, revisit on
usage data. A Likes / "who liked you" tab is post-launch: no backend exists for
it (no likes or admirers routes at all), and a fourth tab that cannot be filled
is worse than three that work.

### go_router is deferred, not rejected

The route table uses `onGenerateRoute` because `MainShell` owns the socket's
token-refresh hook, the lifecycle resume that rebuilds it, and the initial data
load — and `main.dart` gates auth through `home:`. go_router converts both, which
is where a silent chat outage would come from. Route names and argument types are
shaped to survive the swap unchanged if universal links are ever wanted.

---

## The thing most likely to bite

**Nothing has been looked at on a device.** Four scopes, the Stories rewrite and
every navigation call site have shipped with 624 passing tests and zero minutes
on a real screen. Tests prove wiring, not that a screen looks right or that a tap
lands where it should.

Thirty minutes with a cabled phone and `flutter run --dart-define=APP_ENV=local`
covers all of it, and it is far cheaper than finding out during App Store review.

Worth looking at specifically: the three-tab bar and the Settings gear; distance
labels in Discover (miles for `en_US`); the disabled max-distance slider when
location is off; the profile preview hiding its own like/pass buttons; dark mode
over a bright photo; the Stories tray when you have no matches (it shows only the
"Your story" tile, which is correct but should be seen); and Settings →
Notifications, where the push master switch must NOT grey out the two email
switches.
