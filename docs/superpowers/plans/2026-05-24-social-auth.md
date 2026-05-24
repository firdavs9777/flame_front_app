# Social Auth (Google, Apple, Facebook) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up Google, Apple, and Facebook sign-in buttons so users can authenticate and, if their profile is incomplete, complete it via a trimmed flow before reaching the main app.

**Architecture:** Each social button calls a `SocialAuthService` that runs the native SDK and returns the provider token. That token is passed to the existing `auth_service.dart` API methods, which hit the backend. `AuthProvider` gains a `profileIncomplete` status that routes new social users into `SocialProfileCompletionFlow` — a 4-step wizard (profile info → looking for → bio/interests → photos) that patches the user via `PATCH /v1/users/me` and uploads photos to `POST /v1/users/me/photos`.

**Tech Stack:** Flutter, `google_sign_in ^6.2.1`, `sign_in_with_apple ^6.1.4`, `flutter_facebook_auth ^7.1.1`, Riverpod, existing `ApiClient` / `AuthService` / `UserService`

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Modify | `pubspec.yaml` | Add 3 social auth packages |
| Create | `lib/services/social_auth_service.dart` | Native SDK wrappers (Google, Apple, Facebook) |
| Modify | `lib/providers/auth_provider.dart` | Add `profileIncomplete` status + `socialLogin()` method |
| Modify | `lib/screens/auth/login_screen.dart` | Wire social buttons to `SocialAuthService` |
| Modify | `lib/main.dart` | Route `profileIncomplete` → `SocialProfileCompletionFlow` |
| Create | `lib/screens/auth/registration/social_profile_completion_flow.dart` | 4-step completion wizard |
| Modify | `ios/Runner/Info.plist` | URL schemes + keys for all 3 providers |
| Modify | `ios/Runner/AppDelegate.swift` | Facebook SDK init |

---

## Task 1: Add packages

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add dependencies**

Open `pubspec.yaml` and add under `dependencies:` (after `permission_handler`):

```yaml
  # Social Auth
  google_sign_in: ^6.2.1
  sign_in_with_apple: ^6.1.4
  flutter_facebook_auth: ^7.1.1
```

- [ ] **Step 2: Install**

```bash
flutter pub get
```

Expected output: `Got dependencies!` with no errors.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat: add google_sign_in, sign_in_with_apple, flutter_facebook_auth packages"
```

---

## Task 2: Create SocialAuthService

**Files:**
- Create: `lib/services/social_auth_service.dart`

- [ ] **Step 1: Create the file**

```dart
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

class SocialAuthResult {
  final bool success;
  final String? error;

  // Google / Facebook
  final String? idToken;

  // Apple
  final String? appleIdToken;
  final String? appleAuthorizationCode;

  // Facebook
  final String? facebookAccessToken;

  const SocialAuthResult._({
    required this.success,
    this.error,
    this.idToken,
    this.appleIdToken,
    this.appleAuthorizationCode,
    this.facebookAccessToken,
  });

  factory SocialAuthResult.google(String idToken) =>
      SocialAuthResult._(success: true, idToken: idToken);

  factory SocialAuthResult.apple({
    required String idToken,
    required String authorizationCode,
  }) =>
      SocialAuthResult._(
        success: true,
        appleIdToken: idToken,
        appleAuthorizationCode: authorizationCode,
      );

  factory SocialAuthResult.facebook(String accessToken) =>
      SocialAuthResult._(success: true, facebookAccessToken: accessToken);

  factory SocialAuthResult.failure(String error) =>
      SocialAuthResult._(success: false, error: error);
}

class SocialAuthService {
  static final _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  static Future<SocialAuthResult> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return SocialAuthResult.failure('Sign-in cancelled');

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) return SocialAuthResult.failure('No ID token returned');

      return SocialAuthResult.google(idToken);
    } catch (e) {
      return SocialAuthResult.failure(e.toString());
    }
  }

  static Future<SocialAuthResult> signInWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final idToken = credential.identityToken;
      final authCode = credential.authorizationCode;
      if (idToken == null) return SocialAuthResult.failure('No identity token');

      return SocialAuthResult.apple(
        idToken: idToken,
        authorizationCode: authCode,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return SocialAuthResult.failure('Sign-in cancelled');
      }
      return SocialAuthResult.failure(e.message);
    } catch (e) {
      return SocialAuthResult.failure(e.toString());
    }
  }

  static Future<SocialAuthResult> signInWithFacebook() async {
    try {
      final result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
      );

      if (result.status == LoginStatus.cancelled) {
        return SocialAuthResult.failure('Sign-in cancelled');
      }
      if (result.status != LoginStatus.success || result.accessToken == null) {
        return SocialAuthResult.failure(result.message ?? 'Facebook login failed');
      }

      return SocialAuthResult.facebook(result.accessToken!.tokenString);
    } catch (e) {
      return SocialAuthResult.failure(e.toString());
    }
  }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
flutter analyze lib/services/social_auth_service.dart
```

Expected: no errors (warnings about unused imports are OK at this stage since native setup isn't done yet).

- [ ] **Step 3: Commit**

```bash
git add lib/services/social_auth_service.dart
git commit -m "feat: add SocialAuthService with Google/Apple/Facebook SDK wrappers"
```

---

## Task 3: Extend AuthProvider for social login

**Files:**
- Modify: `lib/providers/auth_provider.dart`

- [ ] **Step 1: Add `profileIncomplete` to `AuthStatus`**

In `lib/providers/auth_provider.dart`, change the enum:

```dart
enum AuthStatus {
  initial,
  unauthenticated,
  authenticated,
  registering,
  profileIncomplete, // social auth user who needs to finish their profile
}
```

- [ ] **Step 2: Add `isProfileIncomplete` getter to `AuthState`**

After the existing `isAuthenticated` getter in `AuthState`:

```dart
bool get isProfileIncomplete => status == AuthStatus.profileIncomplete;
```

- [ ] **Step 3: Add `socialLogin` method to `AuthNotifier`**

Add this method after `register()` in `AuthNotifier`. It accepts the result of `SocialAuthService` and calls the appropriate `_authService` method. After receiving a user, it checks if the profile needs completion:

```dart
Future<bool> socialLogin({
  String? googleIdToken,
  String? appleIdToken,
  String? appleAuthorizationCode,
  String? facebookAccessToken,
}) async {
  state = state.copyWith(isLoading: true, error: null);

  AuthResult result;

  if (googleIdToken != null) {
    result = await _authService.googleSignIn(idToken: googleIdToken);
  } else if (appleIdToken != null && appleAuthorizationCode != null) {
    result = await _authService.appleSignIn(
      idToken: appleIdToken,
      authorizationCode: appleAuthorizationCode,
    );
  } else if (facebookAccessToken != null) {
    result = await _authService.facebookSignIn(accessToken: facebookAccessToken);
  } else {
    state = state.copyWith(isLoading: false, error: 'No social token provided');
    return false;
  }

  if (result.success && result.user != null) {
    final user = result.user!;
    final incomplete = user.photos.isEmpty ||
        (user.interests.isEmpty || user.interests.first.isEmpty);

    state = state.copyWith(
      status: incomplete ? AuthStatus.profileIncomplete : AuthStatus.authenticated,
      user: user,
      isLoading: false,
    );
    return true;
  }

  state = state.copyWith(
    isLoading: false,
    error: result.error ?? 'Social login failed',
  );
  return false;
}
```

- [ ] **Step 4: Verify it compiles**

```bash
flutter analyze lib/providers/auth_provider.dart
```

Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/providers/auth_provider.dart
git commit -m "feat: add profileIncomplete status and socialLogin() to AuthProvider"
```

---

## Task 4: Wire social buttons in LoginScreen

**Files:**
- Modify: `lib/screens/auth/login_screen.dart`

- [ ] **Step 1: Add imports at the top of `login_screen.dart`**

```dart
import 'package:flame/services/social_auth_service.dart';
```

- [ ] **Step 2: Replace the three `_buildSocialButton` calls in `_buildSocialLogin()`**

Replace the entire `Row` with the three buttons with:

```dart
Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    _buildSocialButton(
      icon: Icons.g_mobiledata_rounded,
      label: 'Google',
      onTap: _handleGoogleSignIn,
    ),
    const SizedBox(width: 16),
    _buildSocialButton(
      icon: Icons.apple_rounded,
      label: 'Apple',
      onTap: _handleAppleSignIn,
    ),
    const SizedBox(width: 16),
    _buildSocialButton(
      icon: Icons.facebook_rounded,
      label: 'Facebook',
      onTap: _handleFacebookSignIn,
    ),
  ],
),
```

- [ ] **Step 3: Update `_buildSocialButton` signature to accept a callback**

Replace the existing `_buildSocialButton` method:

```dart
Widget _buildSocialButton({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
}) {
  return Container(
    width: 60,
    height: 60,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.1),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 28, color: AppTheme.textPrimary),
    ),
  );
}
```

- [ ] **Step 4: Add the three handler methods**

Add these methods to `_LoginScreenState`:

```dart
Future<void> _handleGoogleSignIn() async {
  final socialResult = await SocialAuthService.signInWithGoogle();
  if (!mounted) return;
  if (!socialResult.success) {
    if (socialResult.error != 'Sign-in cancelled') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(socialResult.error ?? 'Google sign-in failed')),
      );
    }
    return;
  }
  await ref.read(authProvider.notifier).socialLogin(
    googleIdToken: socialResult.idToken,
  );
}

Future<void> _handleAppleSignIn() async {
  final socialResult = await SocialAuthService.signInWithApple();
  if (!mounted) return;
  if (!socialResult.success) {
    if (socialResult.error != 'Sign-in cancelled') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(socialResult.error ?? 'Apple sign-in failed')),
      );
    }
    return;
  }
  await ref.read(authProvider.notifier).socialLogin(
    appleIdToken: socialResult.appleIdToken,
    appleAuthorizationCode: socialResult.appleAuthorizationCode,
  );
}

Future<void> _handleFacebookSignIn() async {
  final socialResult = await SocialAuthService.signInWithFacebook();
  if (!mounted) return;
  if (!socialResult.success) {
    if (socialResult.error != 'Sign-in cancelled') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(socialResult.error ?? 'Facebook sign-in failed')),
      );
    }
    return;
  }
  await ref.read(authProvider.notifier).socialLogin(
    facebookAccessToken: socialResult.facebookAccessToken,
  );
}
```

- [ ] **Step 5: Verify it compiles**

```bash
flutter analyze lib/screens/auth/login_screen.dart
```

Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/auth/login_screen.dart
git commit -m "feat: wire Google/Apple/Facebook buttons in LoginScreen"
```

---

## Task 5: Create SocialProfileCompletionFlow

**Files:**
- Create: `lib/screens/auth/registration/social_profile_completion_flow.dart`

This widget reuses the existing step widgets but skips email/password and email verification. At the end it calls `PATCH /v1/users/me` + `POST /v1/users/me/photos`.

- [ ] **Step 1: Create the file**

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image/image.dart' as img;
import 'package:flame/theme/app_theme.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/user_service.dart';
import 'steps/step_profile_info.dart';
import 'steps/step_looking_for.dart';
import 'steps/step_bio_interests.dart';
import 'steps/step_photos.dart';
import 'registration_flow.dart';

class SocialProfileCompletionFlow extends ConsumerStatefulWidget {
  const SocialProfileCompletionFlow({super.key});

  @override
  ConsumerState<SocialProfileCompletionFlow> createState() =>
      _SocialProfileCompletionFlowState();
}

class _SocialProfileCompletionFlowState
    extends ConsumerState<SocialProfileCompletionFlow> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 4;
  final RegistrationData _data = RegistrationData();
  bool _isUploading = false;

  final List<String> _stepTitles = [
    'About You',
    'Looking For',
    'Your Interests',
    'Add Photos',
  ];

  final List<String> _stepSubtitles = [
    'Tell us a bit about yourself',
    'Who would you like to meet?',
    'What makes you, you?',
    'Show off your best self',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Pre-fill name from the authenticated social user
    if (_data.name.isEmpty && authState.user != null) {
      _data.name = authState.user!.name;
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader().animate().fadeIn(duration: 400.ms),
              const SizedBox(height: 16),
              _buildProgressIndicator()
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 400.ms),
              const SizedBox(height: 24),
              _buildStepInfo()
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 400.ms),
              const SizedBox(height: 24),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentStep = i),
                  children: [
                    StepProfileInfo(data: _data, onNext: _goToNextStep),
                    StepLookingFor(data: _data, onNext: _goToNextStep),
                    StepBioInterests(data: _data, onNext: _goToNextStep),
                    StepPhotos(
                      data: _data,
                      isLoading: _isUploading,
                      onComplete: _handleComplete,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            IconButton(
              onPressed: () => _pageController.previousPage(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
              ),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 20),
              ),
            )
          else
            const SizedBox(width: 48),
          Text(
            'Step ${_currentStep + 1} of $_totalSteps',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: List.generate(_totalSteps, (index) {
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: index < _totalSteps - 1 ? 8 : 0),
              decoration: BoxDecoration(
                color: index <= _currentStep
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _stepTitles[_currentStep],
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _stepSubtitles[_currentStep],
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  void _goToNextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _handleComplete() async {
    setState(() => _isUploading = true);

    try {
      final userService = UserService();

      // 1. Update profile info
      final profileResult = await userService.updateProfile(
        name: _data.name,
        bio: _data.bio,
        interests: _data.interests,
        lookingFor: _data.lookingFor,
        age: _data.age,
      );

      if (!profileResult.success) {
        _showError(profileResult.error ?? 'Failed to update profile');
        setState(() => _isUploading = false);
        return;
      }

      // 2. Upload photos
      String? tempPath;
      try {
        final dir = await Directory.systemTemp.createTemp('flame_photos');
        tempPath = dir.path;
      } catch (_) {
        tempPath = Directory.systemTemp.path;
      }

      for (int i = 0; i < _data.photoFiles.length; i++) {
        final file = _data.photoFiles[i];
        final isPrimary = i == 0;
        try {
          final compressed = await _compressImage(file, tempPath, i);
          await userService.uploadPhoto(compressed, isPrimary: isPrimary);
        } catch (e) {
          debugPrint('Photo upload error: $e');
        }
      }

      // 3. Refresh user and mark authenticated
      final userResult = await userService.getCurrentUser();
      if (userResult.success && userResult.data != null) {
        ref.read(authProvider.notifier).updateUser(userResult.data!);
      }
      ref.read(authProvider.notifier).markAuthenticated();

    } catch (e) {
      setState(() => _isUploading = false);
      _showError('Error: ${e.toString()}');
    }
  }

  Future<File> _compressImage(File file, String tempPath, int index) async {
    try {
      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return file;

      const maxSize = 800;
      if (image.width > maxSize || image.height > maxSize) {
        image = image.width > image.height
            ? img.copyResize(image, width: maxSize)
            : img.copyResize(image, height: maxSize);
      }

      final compressedBytes = img.encodeJpg(image, quality: 70);
      final out = File('$tempPath/photo_$index.jpg');
      await out.writeAsBytes(compressedBytes);
      return out;
    } catch (_) {
      return file;
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
```

- [ ] **Step 2: Add `markAuthenticated()` to `AuthNotifier`** in `lib/providers/auth_provider.dart`

```dart
void markAuthenticated() {
  state = state.copyWith(status: AuthStatus.authenticated);
}
```

- [ ] **Step 3: Verify it compiles**

```bash
flutter analyze lib/screens/auth/registration/social_profile_completion_flow.dart lib/providers/auth_provider.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/auth/registration/social_profile_completion_flow.dart lib/providers/auth_provider.dart
git commit -m "feat: add SocialProfileCompletionFlow and markAuthenticated"
```

---

## Task 6: Route profileIncomplete in main.dart

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Add import**

```dart
import 'screens/auth/registration/social_profile_completion_flow.dart';
```

- [ ] **Step 2: Update the `home` routing**

Replace:

```dart
home: SplashScreen(
  child: authState.isAuthenticated ? const MainShell() : const WelcomeScreen(),
),
```

With:

```dart
home: SplashScreen(
  child: authState.isAuthenticated
      ? const MainShell()
      : authState.isProfileIncomplete
          ? const SocialProfileCompletionFlow()
          : const WelcomeScreen(),
),
```

- [ ] **Step 3: Verify it compiles**

```bash
flutter analyze lib/main.dart
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/main.dart
git commit -m "feat: route profileIncomplete users to SocialProfileCompletionFlow"
```

---

## Task 7: iOS native configuration

**Files:**
- Modify: `ios/Runner/Info.plist`
- Modify: `ios/Runner/AppDelegate.swift`

> **Prerequisites:** You need 3 values before this task:
> - `GOOGLE_CLIENT_ID` — from Google Cloud Console (iOS client ID, looks like `123456789-abc.apps.googleusercontent.com`)
> - `FACEBOOK_APP_ID` — from Meta Developer Console
> - `FACEBOOK_CLIENT_TOKEN` — from Meta Developer Console → Settings → Advanced

- [ ] **Step 1: Add Google, Apple, Facebook entries to `ios/Runner/Info.plist`**

Inside the root `<dict>` (before the closing `</dict>`), add:

```xml
<!-- Google Sign-In URL scheme -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <!-- Replace with your reversed Google client ID e.g. com.googleusercontent.apps.123456789-abc -->
            <string>YOUR_REVERSED_GOOGLE_CLIENT_ID</string>
        </array>
    </dict>
</array>

<!-- Google client ID -->
<key>GIDClientID</key>
<string>YOUR_GOOGLE_CLIENT_ID</string>

<!-- Facebook -->
<key>FacebookAppID</key>
<string>YOUR_FACEBOOK_APP_ID</string>
<key>FacebookClientToken</key>
<string>YOUR_FACEBOOK_CLIENT_TOKEN</string>
<key>FacebookDisplayName</key>
<string>Flame</string>
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>fbapi</string>
    <string>fbapi20130214</string>
    <string>fbapi20130410</string>
    <string>fbapi20130702</string>
    <string>fbapi20131010</string>
    <string>fbapi20131219</string>
    <string>fbapi20140410</string>
    <string>fbapi20140116</string>
    <string>fbapi20150313</string>
    <string>fbapi20150629</string>
    <string>fbapi20160328</string>
    <string>fbapiefr20151011</string>
    <string>fbauth</string>
    <string>fbauth2</string>
    <string>fbshareextension</string>
</array>
```

- [ ] **Step 2: Update `ios/Runner/AppDelegate.swift`**

Replace the existing content with:

```swift
import UIKit
import Flutter
import FacebookCore

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    ApplicationDelegate.shared.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    ApplicationDelegate.shared.application(app, open: url, options: options)
  }
}
```

- [ ] **Step 3: Enable Sign in with Apple capability in Xcode**

Open `ios/Runner.xcworkspace` in Xcode → select Runner target → Signing & Capabilities → `+` → add **Sign in with Apple**.

- [ ] **Step 4: Do a clean build**

```bash
flutter clean && flutter pub get
flutter run -d "iPhone 15 Pro"
```

Expected: app builds and runs with no missing plugin errors.

- [ ] **Step 5: Commit**

```bash
git add ios/Runner/Info.plist ios/Runner/AppDelegate.swift
git commit -m "feat: configure iOS for Google, Apple, Facebook sign-in"
```

---

## Task 8: Backend — fill in credentials

**Files:**
- Modify: `/Users/firdavsmutalipov/Desktop/Flame/flame_backend/.env` (or equivalent secrets file)

- [ ] **Step 1: Set the values**

In the backend's environment configuration, set:

```
GOOGLE_CLIENT_ID=<your iOS client ID from Google Cloud Console>
APPLE_CLIENT_ID=<your Apple Services ID (com.yourcompany.flame)>
FACEBOOK_APP_ID=<your Facebook App ID>
FACEBOOK_APP_SECRET=<your Facebook App Secret>
```

Note: `GOOGLE_CLIENT_ID` must be the **iOS client ID** (not the web client ID) so the backend can verify tokens issued to the iOS app.

- [ ] **Step 2: Restart the backend and verify the health endpoint**

```bash
curl https://api.flame.banatalk.com/health
```

Expected: `{"status":"healthy","version":"1.0.0"}`

---

## Self-Review Checklist

- [x] `SocialAuthResult` types match what `socialLogin()` in `AuthProvider` expects
- [x] `markAuthenticated()` exists before `SocialProfileCompletionFlow` calls it
- [x] `profileIncomplete` status checked in `main.dart` routing
- [x] Photo compression in `SocialProfileCompletionFlow` uses same JPEG output as `RegistrationFlow`
- [x] Cancelled sign-ins are silently ignored (no error SnackBar)
- [x] `UserService.uploadPhoto()` (authenticated endpoint) used in completion flow, not the registration endpoint
- [x] All 3 providers handled in `socialLogin()` with null-safe guards
