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
  // serverClientId is the Google **Web** OAuth client ID. Setting it makes
  // the iOS/Android SDKs mint an ID token whose `aud` claim is the Web
  // client ID, which is what the backend verifies against. Without this,
  // tokens are audienced to the iOS client ID and the backend rejects them
  // with "Invalid Google token".
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
