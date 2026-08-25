import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/validation/auth_validators.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/screens/auth/widgets/auth_gradient_scaffold.dart';
import 'package:flame/screens/auth/widgets/auth_snackbar.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/kit/kit.dart';

/// Requests a password-reset email.
///
/// Gated off — `EnvConfig.current.forgotPasswordEnabled` is false in both
/// presets and `/auth/forgot-password` does not exist server-side yet. Kept in
/// the codebase, and in the codebase's shape, so it is ready the day it does.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.error == null) return;
      showAuthSnackBar(
        context,
        message: next.error!,
        type: AuthSnackBarType.error,
      );
      ref.read(authProvider.notifier).clearError();
    });

    return AuthGradientScaffold(
      onBack: () => Navigator.of(context).pop(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 40),
            _buildHeader()
                .animate()
                .fadeIn(delay: 100.ms, duration: 500.ms)
                .slideX(begin: -0.1, end: 0, delay: 100.ms, duration: 500.ms),
            const SizedBox(height: 48),
            if (_emailSent)
              _buildSuccessCard()
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .scale(
                    begin: const Offset(0.95, 0.95),
                    end: const Offset(1, 1),
                  )
            else
              _buildFormCard(authState)
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 600.ms)
                  .slideY(begin: 0.1, end: 0, delay: 200.ms, duration: 600.ms),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _emailSent
              ? context.l10n.forgotPasswordSentTitle
              : context.l10n.forgotPasswordTitle,
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _emailSent
              ? context.l10n.forgotPasswordSentSubtitle
              : context.l10n.forgotPasswordSubtitle,
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard(AuthState authState) {
    return AppCard(
      padding: const EdgeInsets.all(24),
      borderRadius: AppRadius.borderXXL,
      boxShadow: AppShadows.lg,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppInput(
              controller: _emailController,
              label: context.l10n.loginEmailLabel,
              hint: context.l10n.loginEmailHint,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              prefixIcon: Icons.email_outlined,
              validator: AuthValidators(context.l10n).email,
              onSubmitted: (_) => _handleSubmit(),
            ),
            const SizedBox(height: 32),
            AppButton(
              text: context.l10n.forgotPasswordSubmit,
              size: AppButtonSize.large,
              isFullWidth: true,
              isLoading: authState.isLoading,
              onPressed: _handleSubmit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    return AppCard(
      padding: const EdgeInsets.all(24),
      borderRadius: AppRadius.borderXXL,
      boxShadow: AppShadows.lg,
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.successColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              size: 40,
              color: AppTheme.successColor,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            context.l10n.forgotPasswordSentHeading,
            style: AppTypography.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.forgotPasswordSentBody,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.gray600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            text: context.l10n.forgotPasswordBackToLogin,
            size: AppButtonSize.large,
            isFullWidth: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 8),
          AppButton(
            text: context.l10n.forgotPasswordRetry,
            variant: AppButtonVariant.ghost,
            isFullWidth: true,
            onPressed: () => setState(() => _emailSent = false),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref
        .read(authProvider.notifier)
        .forgotPassword(_emailController.text.trim());
    if (!mounted) return;

    if (success) setState(() => _emailSent = true);
  }
}
