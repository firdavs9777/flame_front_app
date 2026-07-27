import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/config/env.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/services/social_auth_service.dart';
import 'package:flame/core/i18n/build_context_ext.dart';

enum _Provider { google, apple, facebook }

/// Renders Google / Apple / Facebook sign-in buttons — but ONLY when social
/// auth is enabled. Kept behind [EnvConfig.authSocialEnabled] so the UI is
/// built and shippable while staying invisible until the backend + provider
/// keys are live.
///
/// [enabledOverride] is a test seam: when non-null it takes precedence over the
/// env flag so widget tests can exercise both the shown and hidden states
/// without flipping the real flag.
class SocialSignInButtons extends ConsumerStatefulWidget {
  final bool? enabledOverride;
  final Color dividerColor;
  final Color dividerLabelColor;

  const SocialSignInButtons({
    super.key,
    this.enabledOverride,
    this.dividerColor = AppColors.gray300,
    this.dividerLabelColor = AppColors.gray600,
  });

  @override
  ConsumerState<SocialSignInButtons> createState() =>
      _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends ConsumerState<SocialSignInButtons> {
  _Provider? _loading;

  bool get _enabled =>
      widget.enabledOverride ?? EnvConfig.current.authSocialEnabled;

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        _buildDivider(context),
        const SizedBox(height: 20),
        _SocialButton(
          label: context.l10n.loginGoogle,
          icon: Icons.g_mobiledata_rounded,
          background: AppColors.white,
          foreground: AppColors.gray900,
          border: const BorderSide(color: AppColors.gray300),
          isLoading: _loading == _Provider.google,
          onPressed: _loading == null ? _handleGoogle : null,
        ),
        const SizedBox(height: 12),
        _SocialButton(
          label: context.l10n.loginFacebook,
          icon: Icons.facebook_rounded,
          background: const Color(0xFF1877F2),
          foreground: AppColors.white,
          isLoading: _loading == _Provider.facebook,
          onPressed: _loading == null ? _handleFacebook : null,
        ),
        const SizedBox(height: 12),
        // Apple per HIG: black in light mode, white in dark mode.
        _SocialButton(
          label: context.l10n.loginApple,
          icon: Icons.apple_rounded,
          background: isDark ? AppColors.white : AppColors.black,
          foreground: isDark ? AppColors.black : AppColors.white,
          isLoading: _loading == _Provider.apple,
          onPressed: _loading == null ? _handleApple : null,
        ),
      ],
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: widget.dividerColor)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            context.l10n.loginOrContinueWith,
            style: AppTypography.bodySmall.copyWith(
              color: widget.dividerLabelColor,
            ),
          ),
        ),
        Expanded(child: Divider(color: widget.dividerColor)),
      ],
    );
  }

  Future<void> _handleGoogle() => _run(
        _Provider.google,
        SocialAuthService.signInWithGoogle,
        (result) => ref.read(authProvider.notifier).socialLogin(
              googleIdToken: result.idToken,
            ),
        () => context.l10n.loginGoogleFailed,
      );

  Future<void> _handleApple() => _run(
        _Provider.apple,
        SocialAuthService.signInWithApple,
        (result) => ref.read(authProvider.notifier).socialLogin(
              appleIdToken: result.appleIdToken,
              appleAuthorizationCode: result.appleAuthorizationCode,
            ),
        () => context.l10n.loginAppleFailed,
      );

  Future<void> _handleFacebook() => _run(
        _Provider.facebook,
        SocialAuthService.signInWithFacebook,
        (result) => ref.read(authProvider.notifier).socialLogin(
              facebookAccessToken: result.facebookAccessToken,
            ),
        () => context.l10n.loginFacebookFailed,
      );

  Future<void> _run(
    _Provider provider,
    Future<SocialAuthResult> Function() signIn,
    Future<bool> Function(SocialAuthResult) completeLogin,
    String Function() failedMessage,
  ) async {
    setState(() => _loading = provider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await signIn();
      if (!mounted) return;

      if (!result.success) {
        final msg = result.error == 'Sign-in cancelled'
            ? context.l10n.loginCancelled
            : (result.error ?? failedMessage());
        messenger.showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      await completeLogin(result);
      // Auth state changes are observed by the hosting screen's ref.listen,
      // which routes on success and surfaces backend errors.
    } finally {
      if (mounted) setState(() => _loading = null);
    }
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;
  final BorderSide? border;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _SocialButton({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
    this.border,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          side: border,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMD),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(foreground),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: foreground),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: AppTypography.buttonMedium.copyWith(color: foreground),
                  ),
                ],
              ),
      ),
    );
  }
}
