import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flame/config/env.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/services/social_auth_service.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/screens/auth/widgets/auth_snackbar.dart';

enum _Provider { google, apple, facebook }

// Official brand marks. These are trademarked assets — the SVGs must not be
// redrawn, recoloured (beyond the monochrome tints each brand permits), or
// swapped for lookalike font glyphs. Material's `Icons.g_mobiledata_rounded`
// etc. previously stood in here and are not compliant.
const _kGoogleLogo = 'assets/images/social/google.svg';
const _kAppleLogo = 'assets/images/social/apple.svg';
const _kFacebookLogo = 'assets/images/social/facebook.svg';

// Google's specified light-theme button palette.
const _kGoogleSurface = Color(0xFFFFFFFF);
const _kGoogleOnSurface = Color(0xFF1F1F1F);
const _kGoogleBorder = Color(0xFF747775);

// Facebook Blue.
const _kFacebookBlue = Color(0xFF1877F2);

/// Brand mark size. Google specifies 20dp inside a 40dp-plus button; Apple and
/// Meta both sit comfortably at the same size, so one value keeps the stack
/// optically aligned.
const _kLogoSize = 20.0;

/// Distance from the button's leading edge to the mark, and from the mark to
/// the label. Google specifies 12dp either side of the mark at this size.
const _kLogoInset = 16.0;
const _kLogoGap = 12.0;

/// Renders a brand SVG. [tint] recolours single-colour marks (Apple, Facebook);
/// it is deliberately never applied to Google's multicolour "G".
class _BrandLogo extends StatelessWidget {
  final String asset;
  final Color? tint;

  const _BrandLogo({required this.asset, this.tint});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: _kLogoSize,
      height: _kLogoSize,
      colorFilter: tint == null
          ? null
          : ColorFilter.mode(tint!, BlendMode.srcIn),
    );
  }
}

/// Which social providers should render. Resolved from the per-provider env
/// flags plus the running platform — a provider is shown only when its backend
/// endpoint AND its native config are both usable.
@immutable
class SocialProviderVisibility {
  final bool google;
  final bool apple;
  final bool facebook;

  const SocialProviderVisibility({
    this.google = false,
    this.apple = false,
    this.facebook = false,
  });

  /// Resolves the env flags for [platform].
  ///
  /// Apple is additionally pinned to iOS: [SocialAuthService.signInWithApple]
  /// passes no `webAuthenticationOptions`, so the Android web flow is not
  /// configured and the button could never succeed there.
  factory SocialProviderVisibility.forEnv(
    EnvConfig env,
    TargetPlatform platform,
  ) => SocialProviderVisibility(
    google: env.googleSignInEnabled,
    apple: env.appleSignInEnabled && platform == TargetPlatform.iOS,
    facebook: env.facebookSignInEnabled,
  );

  /// True when at least one provider renders. Gates the divider and the
  /// widget's entire subtree.
  bool get any => google || apple || facebook;
}

/// Renders the Google / Apple / Facebook sign-in buttons that are currently
/// live. Each provider is gated independently so a provider whose native
/// credentials are still missing stays invisible instead of failing at tap
/// time. See docs/social-auth-setup.md for what each one needs.
///
/// [visibilityOverride] is a test seam: when non-null it replaces the resolved
/// env + platform visibility entirely, letting widget tests exercise any
/// combination without flipping real flags.
class SocialSignInButtons extends ConsumerStatefulWidget {
  final SocialProviderVisibility? visibilityOverride;
  final Color dividerColor;
  final Color dividerLabelColor;

  const SocialSignInButtons({
    super.key,
    this.visibilityOverride,
    this.dividerColor = AppColors.gray300,
    this.dividerLabelColor = AppColors.gray600,
  });

  @override
  ConsumerState<SocialSignInButtons> createState() =>
      _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends ConsumerState<SocialSignInButtons> {
  _Provider? _loading;

  SocialProviderVisibility get _visible =>
      widget.visibilityOverride ??
      SocialProviderVisibility.forEnv(EnvConfig.current, defaultTargetPlatform);

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    if (!visible.any) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Built as a list so a hidden provider leaves no stray spacing behind.
    final buttons = <Widget>[
      if (visible.google)
        // Google branding: the four-colour "G" is never recoloured or placed on
        // a tinted surface. White surface, #1F1F1F label, #747775 border.
        _SocialButton(
          label: context.l10n.loginGoogle,
          logo: const _BrandLogo(asset: _kGoogleLogo),
          background: _kGoogleSurface,
          foreground: _kGoogleOnSurface,
          border: const BorderSide(color: _kGoogleBorder),
          isLoading: _loading == _Provider.google,
          onPressed: _loading == null ? _handleGoogle : null,
        ),
      if (visible.facebook)
        // Meta branding: white "f" mark on Facebook Blue.
        _SocialButton(
          label: context.l10n.loginFacebook,
          logo: const _BrandLogo(asset: _kFacebookLogo, tint: AppColors.white),
          background: _kFacebookBlue,
          foreground: AppColors.white,
          isLoading: _loading == _Provider.facebook,
          onPressed: _loading == null ? _handleFacebook : null,
        ),
      if (visible.apple)
        // Apple HIG: black button in light mode, white in dark mode, with the
        // logo always matching the label colour.
        _SocialButton(
          label: context.l10n.loginApple,
          logo: _BrandLogo(
            asset: _kAppleLogo,
            tint: isDark ? AppColors.black : AppColors.white,
          ),
          background: isDark ? AppColors.white : AppColors.black,
          foreground: isDark ? AppColors.black : AppColors.white,
          isLoading: _loading == _Provider.apple,
          onPressed: _loading == null ? _handleApple : null,
        ),
    ];

    return Column(
      children: [
        _buildDivider(context),
        const SizedBox(height: 20),
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          buttons[i],
        ],
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
    (result) => ref
        .read(authProvider.notifier)
        .socialLogin(googleIdToken: result.idToken),
    () => context.l10n.loginGoogleFailed,
  );

  Future<void> _handleApple() => _run(
    _Provider.apple,
    SocialAuthService.signInWithApple,
    (result) => ref
        .read(authProvider.notifier)
        .socialLogin(
          appleIdToken: result.appleIdToken,
          appleAuthorizationCode: result.appleAuthorizationCode,
        ),
    () => context.l10n.loginAppleFailed,
  );

  Future<void> _handleFacebook() => _run(
    _Provider.facebook,
    SocialAuthService.signInWithFacebook,
    (result) => ref
        .read(authProvider.notifier)
        .socialLogin(facebookAccessToken: result.facebookAccessToken),
    () => context.l10n.loginFacebookFailed,
  );

  Future<void> _run(
    _Provider provider,
    Future<SocialAuthResult> Function() signIn,
    Future<bool> Function(SocialAuthResult) completeLogin,
    String Function() failedMessage,
  ) async {
    setState(() => _loading = provider);
    try {
      final result = await signIn();
      if (!mounted) return;

      if (!result.success) {
        final msg = result.error == 'Sign-in cancelled'
            ? context.l10n.loginCancelled
            : (result.error ?? failedMessage());
        showAuthSnackBar(context, message: msg);
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
  final Widget logo;
  final Color background;
  final Color foreground;
  final BorderSide? border;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _SocialButton({
    required this.label,
    required this.logo,
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
                width: _kLogoSize,
                height: _kLogoSize,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(foreground),
                ),
              )
            // Every provider's guidelines put the mark on the leading edge with
            // the label optically centred in the button, so this is a Stack
            // rather than a Row (a Row centres mark+label as one group).
            : Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    // Reserve the mark's footprint on BOTH sides so the label
                    // centres in the button rather than in the leftover space.
                    padding: const EdgeInsets.symmetric(
                      horizontal: _kLogoInset + _kLogoSize + _kLogoGap,
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.buttonMedium.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    start: _kLogoInset,
                    child: ExcludeSemantics(child: logo),
                  ),
                ],
              ),
      ),
    );
  }
}
