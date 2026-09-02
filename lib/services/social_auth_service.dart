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

  /// The name Apple supplied, available on the FIRST authorization only.
  ///
  /// Apple returns givenName/familyName exactly once — the first time this
  /// Apple ID authorizes this app — and never again, not in the ID token and
  /// not on later sign-ins. If it is not captured and persisted at that
  /// moment it is gone for good, and the only way back is for the user to
  /// revoke the app under Settings -> Apple ID -> Sign in with Apple.
  ///
  /// That is why this is forwarded to the server on every Apple sign-in
  /// rather than requested later: there IS no later.
  final String? appleFullName;

  // Facebook
  final String? facebookAccessToken;

  const SocialAuthResult._({
    required this.success,
    this.error,
    this.idToken,
    this.appleIdToken,
    this.appleAuthorizationCode,
    this.appleFullName,
    this.facebookAccessToken,
  });

  factory SocialAuthResult.google(String idToken) =>
      SocialAuthResult._(success: true, idToken: idToken);

  factory SocialAuthResult.apple({
    required String idToken,
    required String authorizationCode,
    String? fullName,
  }) => SocialAuthResult._(
    success: true,
    appleFullName: fullName,
    appleIdToken: idToken,
    appleAuthorizationCode: authorizationCode,
  );

  factory SocialAuthResult.facebook(String accessToken) =>
      SocialAuthResult._(success: true, facebookAccessToken: accessToken);

  factory SocialAuthResult.failure(String error) =>
      SocialAuthResult._(success: false, error: error);
}

class SocialAuthService {
  // serverClientId is the Google **Web** OAuth client ID.
  //
  // NOTE: this does NOT make every platform mint a token audienced to the web
  // client. It works that way on Android, but on iOS the plugin only forwards
  // it to GIDConfiguration.serverClientID, which Google uses for the server
  // auth code. Verified on device: `aud` came back as the **iOS** client ID and
  // serverAuthCode was null.
  //
  // So the backend must accept every client ID we own, not just this one — see
  // FLAME_GOOGLE_CLIENT_ID (a comma-separated list) in flame/utils/socialVerify.js.
  static final _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId:
        '55426082662-47qes5149r092q7tkmmngntiur3r1i9c.apps.googleusercontent.com',
  );

  static Future<SocialAuthResult> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return SocialAuthResult.failure('Sign-in cancelled');

      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        return SocialAuthResult.failure('No ID token returned');
      }

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
        fullName: _appleName(credential.givenName, credential.familyName),
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

  /// Joins whichever name parts Apple returned.
  ///
  /// Either part can be null even on a first authorization — the user can edit
  /// what they share on Apple's sheet, and some Apple IDs simply have no family
  /// name. Returns null rather than an empty string so the server can tell
  /// "not supplied" from "supplied as blank".
  static String? _appleName(String? given, String? family) {
    final parts = [given, family]
        .map((p) => p?.trim() ?? '')
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(' ');
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
        return SocialAuthResult.failure(
          result.message ?? 'Facebook login failed',
        );
      }

      return SocialAuthResult.facebook(result.accessToken!.tokenString);
    } catch (e) {
      return SocialAuthResult.failure(e.toString());
    }
  }
}
