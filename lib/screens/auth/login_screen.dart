import 'package:flame/core/navigation/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flame/config/env.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/i18n/error_messages.dart';
import 'package:flame/core/validation/auth_validators.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/widgets/auth/social_sign_in_buttons.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (previous, next) {
      // Both terminal states mean this pushed route has to get out of the way:
      // main.dart's `home:` has already swapped to MainShell or to the profile
      // completion flow underneath it.
      if (next.isAuthenticated || next.isProfileIncomplete) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      if (next.error != null) {
        final message = translateApiError(
          context.l10n,
          ApiResponse(
            success: false,
            error: next.error,
            errorCode: null, // AuthState doesn't carry errorCode yet — Phase 1 work
            statusCode: 0,
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        ref.read(authProvider.notifier).clearError();
      }
    });

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFF6B6B),
              Color(0xFFFF8E53),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // Back Button
                  _buildBackButton()
                      .animate()
                      .fadeIn(duration: 400.ms),

                  const SizedBox(height: 40),

                  // Header
                  _buildHeader()
                      .animate()
                      .fadeIn(delay: 100.ms, duration: 500.ms)
                      .slideX(begin: -0.1, end: 0, delay: 100.ms, duration: 500.ms),

                  const SizedBox(height: 48),

                  // Login Form Card
                  _buildLoginCard(authState)
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 600.ms)
                      .slideY(begin: 0.1, end: 0, delay: 200.ms, duration: 600.ms),

                  const SizedBox(height: 32),

                  // Social Login (self-gates on authSocialEnabled).
                  const SocialSignInButtons()
                      .animate()
                      .fadeIn(delay: 400.ms, duration: 600.ms),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return IconButton(
      onPressed: () => Navigator.of(context).pop(),
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.loginTitle,
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          context.l10n.loginSubtitle,
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard(AuthState authState) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Email Field
            _buildEmailField(),
            const SizedBox(height: 20),

            // Password Field
            _buildPasswordField(),
            const SizedBox(height: 16),

            // Remember Me & Forgot Password
            _buildRememberForgot(),
            const SizedBox(height: 32),

            // Login Button
            _buildLoginButton(authState),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    final validators = AuthValidators(context.l10n);
    return AppInput(
      controller: _emailController,
      label: context.l10n.loginEmailLabel,
      hint: context.l10n.loginEmailHint,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      prefixIcon: Icons.email_outlined,
      validator: validators.email,
    );
  }

  Widget _buildPasswordField() {
    final validators = AuthValidators(context.l10n);
    return AppInput(
      controller: _passwordController,
      label: context.l10n.loginPasswordLabel,
      hint: context.l10n.loginPasswordHint,
      obscureText: true,
      textInputAction: TextInputAction.done,
      prefixIcon: Icons.lock_outline_rounded,
      onSubmitted: (_) => _handleLogin(),
      // Presence only. A minimum here would lock out any existing account
      // whose password is shorter than today's registration rule.
      validator: validators.requiredField,
    );
  }

  Widget _buildRememberForgot() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _rememberMe,
                onChanged: (value) => setState(() => _rememberMe = value!),
                activeColor: AppTheme.primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              context.l10n.loginRememberMe,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        if (EnvConfig.current.forgotPasswordEnabled)
          TextButton(
            onPressed: () {
              Navigator.of(context).pushNamed(
                AppRoutes.forgotPassword,
              );
            },
            child: Text(
              context.l10n.loginForgotPassword,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryColor,
              ),
            ),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildLoginButton(AuthState authState) {
    // Showcase: the design-system AppButton replaces the hand-rolled button.
    return AppButton(
      text: context.l10n.loginSubmit,
      onPressed: _handleLogin,
      size: AppButtonSize.large,
      isFullWidth: true,
      isLoading: authState.isLoading,
    );
  }

  void _handleLogin() {
    if (_formKey.currentState!.validate()) {
      ref.read(authProvider.notifier).login(
            _emailController.text.trim(),
            _passwordController.text,
          );
    }
  }
}
