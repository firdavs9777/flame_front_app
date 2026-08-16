# Social auth setup

All the Dart code is written and all three endpoints exist on prod. What gates
each provider is credentials — on the **backend** and in **native config** — so
each one has its own flag in `lib/config/env.dart`.

A provider's button only renders when its flag is `true`. Flip a flag **only
after** completing its section below — a flag on without credentials produces a
button that fails at tap time.

| Provider | Flag | Backend | iOS | Android |
|---|---|---|---|---|
| Google | `googleSignInEnabled` | ✅ configured | ✅ live | ⚠️ needs OAuth client (§1) |
| Apple | `appleSignInEnabled` | ❌ not configured | ❌ needs capability (§2) | n/a — not supported |
| Facebook | `facebookSignInEnabled` | ❌ not configured | ❌ needs Meta app (§3) | ❌ needs Meta app (§3) |

### Checking backend readiness

Probe the endpoint with a junk token. The error code tells you the state:

```bash
B=https://api.banatalk.com/flamebackend/v1
curl -s -X POST $B/auth/google   -H 'Content-Type: application/json' -d '{"id_token":"x"}'
curl -s -X POST $B/auth/apple    -H 'Content-Type: application/json' -d '{"id_token":"x","authorization_code":"y"}'
curl -s -X POST $B/auth/facebook -H 'Content-Type: application/json' -d '{"access_token":"x"}'
```

- `INVALID_SOCIAL_TOKEN` → provider **is** configured; it tried to verify and the
  junk token failed. This is what you want.
- `PROVIDER_NOT_CONFIGURED` → the backend has no credentials for that provider.
  Native setup alone will not make it work.
- `VALIDATION` → wrong field names in the request body.

As of this writing Google returns `INVALID_SOCIAL_TOKEN`; Apple and Facebook
return `PROVIDER_NOT_CONFIGURED`. **Both need backend env vars in addition to the
native setup below** — see the "Backend" step in each section.

### Where the backend lives

The live API is **not** `~/Desktop/Flame/flame_backend` (that Python service
deploys to `api.flame.banatalk.com`, which currently has no listener on 80 or
443). The app talks to `api.banatalk.com/flamebackend/v1`, served by the Node
app at:

```
~/Projects/BananaTalk/backend/flame
```

Relevant files: `utils/socialVerify.js` (verification + the `isConfigured`
gate), `controllers/socialAuthController.js`, `services/socialAuthService.js`.

**No backend code changes are needed for any provider.** All three verifiers are
implemented and `apple-signin-auth`, `google-auth-library` and `axios` are all
installed. `isConfigured()` gates purely on environment variables, so setting
them is the entire backend task:

| Provider | Required env vars |
|---|---|
| Google | `FLAME_GOOGLE_CLIENT_ID` |
| Apple | `FLAME_APPLE_CLIENT_ID` |
| Facebook | `FLAME_FACEBOOK_APP_ID` **and** `FLAME_FACEBOOK_APP_SECRET` |

> **App Store blocker.** Guideline 4.8 requires Sign in with Apple on any iOS
> build that offers another third-party login. Google is now on, so **§2 must be
> done before submitting to the App Store.** TestFlight and dev builds are fine.

---

## 1. Google — Android OAuth client

iOS is already done (client ID, `GIDClientID`, URL scheme, and `serverClientId`
in `lib/services/social_auth_service.dart` so the token audience matches what the
backend verifies).

Android needs **no files** — `google_sign_in` 6.x does not require
`google-services.json`. It needs one console registration. Until then, Android
Google sign-in returns `PlatformException(sign_in_failed, ..., 10)`.

**Get your SHA-1 fingerprints:**

```bash
# Debug (the auto-generated debug keystore)
keytool -list -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android | grep SHA1

# Release — run against whatever keystore signs your release builds
keytool -list -v -keystore <path/to/release.keystore> -alias <alias> | grep SHA1
```

**Register them:**

1. Open [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials)
   for project `55426082662` (the project that owns the existing iOS client).
2. **Create Credentials → OAuth client ID → Android**.
3. Package name: `com.flame.flame`
4. SHA-1: paste the debug fingerprint. Repeat for the release fingerprint as a
   second Android client.

No code change. Android starts working once the client propagates (a few minutes).

> Note: `android/app/build.gradle.kts` currently signs release builds with the
> **debug** signing config. Register a real release keystore's SHA-1 once that is
> fixed, or release builds will fail Google sign-in.

---

## 2. Apple — Sign in with Apple capability

Nothing exists yet: there is no `Runner.entitlements` and no
`CODE_SIGN_ENTITLEMENTS` in `project.pbxproj`. The button is hidden on Android
unconditionally (the Dart code passes no `webAuthenticationOptions`, so the
Android web flow is not configured).

**Backend: one variable.** `/auth/apple` returns `PROVIDER_NOT_CONFIGURED` only
because `FLAME_APPLE_CLIENT_ID` is unset. Set it to the bundle ID:

```
FLAME_APPLE_CLIENT_ID=com.flame.flame
```

That is the `aud` claim `apple-signin-auth` verifies the identity token against.
**No Team ID, Key ID or `.p8` private key is required** — `socialVerify.js`
only calls `verifyIdToken`, and the `authorization_code` the client sends is
never exchanged with Apple. (A `.p8` would only be needed to add token refresh
or server-side revocation later.)

The client is already correct: it posts `{id_token, authorization_code}`, and
the endpoint reads `id_token`.

### Native setup

1. In the [Apple Developer portal](https://developer.apple.com/account/resources/identifiers/list),
   open the App ID `com.flame.flame` (team `RJF4T5CJ76`) and enable
   **Sign in with Apple**. Regenerate the provisioning profiles.

   > Your team already ships Sign in with Apple on other App IDs
   > (`com.bananatalk.bananatalkApp`, `tezsell.com.app`), so the account has the
   > needed role — this is only unset for `com.flame.flame`.

2. In Xcode: open `ios/Runner.xcworkspace`, select the **Runner** target →
   **Signing & Capabilities** → **+ Capability** → **Sign in with Apple**.
   This creates `ios/Runner/Runner.entitlements` containing:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>com.apple.developer.applesignin</key>
     <array>
       <string>Default</string>
     </array>
   </dict>
   </plist>
   ```

   and adds `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;` to every build
   configuration in `project.pbxproj`.

   > Do this through Xcode rather than by hand — adding the file without the
   > portal capability makes code signing fail.

3. Confirm the backend verifies the `aud` claim against bundle ID
   `com.flame.flame`.

4. Set `appleSignInEnabled: true` in **both** `_local` and `_prod` in
   `lib/config/env.dart`, and update `test/config/env_flags_test.dart`.

**Test on a real device.** Sign in with Apple does not work in the Simulator
unless an Apple ID is signed in under Settings.

---

## 3. Facebook — Meta app

`ios/Runner/Info.plist` holds literal `YOUR_FACEBOOK_APP_ID` /
`YOUR_FACEBOOK_CLIENT_TOKEN` placeholders, and Android has no Facebook
configuration at all.

**Backend: two variables.** `/auth/facebook` returns `PROVIDER_NOT_CONFIGURED`
until **both** are set — `isConfigured('facebook')` requires the pair:

```
FLAME_FACEBOOK_APP_ID=<app id>
FLAME_FACEBOOK_APP_SECRET=<app secret>
```

They are combined into the `<id>|<secret>` app token used to call
`/debug_token`, which confirms the access token was issued for this exact app.
Same Meta app as the client — create it below first, then set these.

### Create the app

1. [Meta for Developers](https://developers.facebook.com/apps) → **Create App** →
   type **Consumer** → add the **Facebook Login** product.
2. Note the **App ID** (Settings → Basic) and **Client Token**
   (Settings → Advanced → Security).
3. Under Facebook Login → Settings, keep **Client OAuth Login** and
   **Embedded Browser OAuth Login** enabled.
4. Add both platforms under Settings → Basic:
   - **iOS**: bundle ID `com.flame.flame`
   - **Android**: package `com.flame.flame`, class
     `com.flame.flame.MainActivity`, plus the **key hashes** (see below).
5. The app must be switched **Live** (not Development) before non-testers can
   log in, which requires a privacy policy URL and App Review for
   `public_profile` + `email`.

**Android key hash:**

```bash
keytool -exportcert -alias androiddebugkey -keystore ~/.android/debug.keystore \
  -storepass android -keypass android | openssl sha1 -binary | openssl base64
```

### iOS edits — `ios/Runner/Info.plist`

Replace the placeholders:

```xml
<key>FacebookAppID</key>
<string>YOUR_ACTUAL_APP_ID</string>
<key>FacebookClientToken</key>
<string>YOUR_ACTUAL_CLIENT_TOKEN</string>
```

Add a second entry to the existing `CFBundleURLTypes` array (do **not** replace
the Google one already there):

```xml
<dict>
  <key>CFBundleTypeRole</key>
  <string>Editor</string>
  <key>CFBundleURLSchemes</key>
  <array>
    <string>fbYOUR_ACTUAL_APP_ID</string>
  </array>
</dict>
```

`LSApplicationQueriesSchemes` already contains the `fbapi` entries.

### Android edits

Create `android/app/src/main/res/values/strings.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="facebook_app_id">YOUR_ACTUAL_APP_ID</string>
    <string name="fb_login_protocol_scheme">fbYOUR_ACTUAL_APP_ID</string>
    <string name="facebook_client_token">YOUR_ACTUAL_CLIENT_TOKEN</string>
</resources>
```

In `android/app/src/main/AndroidManifest.xml`, inside `<application>`:

```xml
<meta-data android:name="com.facebook.sdk.ApplicationId"
    android:value="@string/facebook_app_id"/>
<meta-data android:name="com.facebook.sdk.ClientToken"
    android:value="@string/facebook_client_token"/>

<activity android:name="com.facebook.FacebookActivity"
    android:configChanges="keyboard|keyboardHidden|screenLayout|screenSize|orientation"
    android:label="@string/app_name" />
<activity
    android:name="com.facebook.CustomTabActivity"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="@string/fb_login_protocol_scheme" />
    </intent-filter>
</activity>
```

And inside the top-level `<queries>` block:

```xml
<package android:name="com.facebook.katana" />
```

> The `ApplicationId` meta-data is mandatory — the Facebook SDK throws on
> initialization without it. That is why these entries are not committed with
> placeholder values.

### Enable

Set `facebookSignInEnabled: true` in both `_local` and `_prod` in
`lib/config/env.dart`, and update `test/config/env_flags_test.dart`.

---

## 4. Brand marks (already done)

The buttons render each provider's official mark from
`assets/images/social/{google,apple,facebook}.svg` via `flutter_svg`. These
replaced Material lookalike glyphs (`Icons.g_mobiledata_rounded` etc.), which
are not compliant with any of the three providers' branding guidelines and can
block Google OAuth verification and App Store review.

Rules baked into `social_sign_in_buttons.dart`:

- **Google's "G" is never recoloured** and always sits on a white surface with
  the `#1F1F1F` label and `#747775` border Google specifies.
- **Apple's mark always matches the label colour** — white on the black button
  in light mode, black on the white button in dark mode, per the HIG.
- **Facebook's "f" is white on Facebook Blue** `#1877F2`.
- The mark sits on the leading edge with the label optically centred in the
  button, which is why the layout is a `Stack` rather than a `Row`.

Two tests guard this: `social_button_branding_test.dart` asserts the SVGs render
and the Material lookalikes do not, and `social_button_golden_test.dart` pixel-
diffs the rendered buttons — the only thing that catches a malformed SVG path.
Regenerate the golden with:

```bash
flutter test test/widgets/auth/social_button_golden_test.dart --update-goldens
```

---

## Verifying a provider end to end

```bash
flutter test                                   # flags + visibility gating
flutter run --dart-define=APP_ENV=local        # against a local backend
flutter run                                    # against prod
```

Tap the provider's button and confirm the backend returns tokens rather than
`INVALID_SOCIAL_TOKEN`. A new social user lands in `SocialProfileCompletionFlow`
(wired in `lib/main.dart`); a returning one goes straight to the main app.
