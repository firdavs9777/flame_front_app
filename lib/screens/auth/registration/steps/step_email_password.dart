import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/providers/auth_availability_provider.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/screens/auth/registration/legal_document_sheet.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/navigation/app_routes.dart';
import 'package:flame/core/validation/auth_validators.dart';
import 'package:flame/widgets/kit/kit.dart';

class StepEmailPassword extends ConsumerStatefulWidget {
  final RegistrationData data;
  final VoidCallback onNext;

  const StepEmailPassword({
    super.key,
    required this.data,
    required this.onNext,
  });

  @override
  ConsumerState<StepEmailPassword> createState() => _StepEmailPasswordState();
}

class _StepEmailPasswordState extends ConsumerState<StepEmailPassword> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _agreedToTerms = false;
  bool _checking = false;
  String? _emailAvailabilityError;

  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.data.email;
    _passwordController.text = widget.data.password;
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => showLegalDocumentSheet(context, LegalDoc.terms);
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => showLegalDocumentSheet(context, LegalDoc.privacy);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AppCard(
        padding: const EdgeInsets.all(24),
        borderRadius: AppRadius.borderXXL,
        boxShadow: AppShadows.lg,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Email Field
              _buildEmailField()
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 400.ms)
                  .slideX(begin: 0.1, end: 0, delay: 100.ms, duration: 400.ms),

              if (_emailAvailabilityError != null) _buildEmailAvailabilityError(),

              const SizedBox(height: 20),

              // Password Field
              _buildPasswordField()
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 400.ms)
                  .slideX(begin: 0.1, end: 0, delay: 200.ms, duration: 400.ms),

              const SizedBox(height: 20),

              // Confirm Password Field
              _buildConfirmPasswordField()
                  .animate()
                  .fadeIn(delay: 300.ms, duration: 400.ms)
                  .slideX(begin: 0.1, end: 0, delay: 300.ms, duration: 400.ms),

              const SizedBox(height: 16),

              // Password requirements
              _buildPasswordRequirements()
                  .animate()
                  .fadeIn(delay: 400.ms, duration: 400.ms),

              const SizedBox(height: 20),

              // Terms & Privacy consent
              _buildConsentRow()
                  .animate()
                  .fadeIn(delay: 450.ms, duration: 400.ms),

              const SizedBox(height: 24),

              // Continue Button
              _buildContinueButton()
                  .animate()
                  .fadeIn(delay: 500.ms, duration: 400.ms)
                  .slideY(begin: 0.2, end: 0, delay: 500.ms, duration: 400.ms),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, duration: 400.ms),
    );
  }

  Widget _buildEmailField() {
    final validators = AuthValidators(context.l10n);
    return AppInput(
      controller: _emailController,
      label: 'Email Address',
      hint: 'you@example.com',
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      prefixIcon: Icons.email_outlined,
      onChanged: (_) {
        if (_emailAvailabilityError != null) {
          setState(() => _emailAvailabilityError = null);
        }
      },
      validator: validators.email,
    );
  }

  Widget _buildEmailAvailabilityError() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 16, color: AppTheme.errorColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _emailAvailabilityError!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.errorColor,
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.of(context)
                  .pushReplacementNamed(AppRoutes.login),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppTheme.primaryColor,
              ),
              child: Text(
                context.l10n.registerLogInInstead,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField() {
    final validators = AuthValidators(context.l10n);
    return AppInput(
      controller: _passwordController,
      label: 'Password',
      hint: 'Create a strong password',
      obscureText: true,
      textInputAction: TextInputAction.next,
      prefixIcon: Icons.lock_outline_rounded,
      onChanged: (_) => setState(() {}), // live-update the strength hints
      validator: validators.password,
    );
  }

  Widget _buildConfirmPasswordField() {
    final validators = AuthValidators(context.l10n);
    return AppInput(
      controller: _confirmPasswordController,
      label: 'Confirm Password',
      hint: 'Confirm your password',
      obscureText: true,
      textInputAction: TextInputAction.done,
      prefixIcon: Icons.lock_outline_rounded,
      validator: (value) => validators.confirmPassword(
        value,
        against: _passwordController.text,
      ),
    );
  }

  Widget _buildPasswordRequirements() {
    final password = _passwordController.text;
    final hasLength = password.length >= kMinPasswordLength;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.gray100,
        borderRadius: AppRadius.borderMD,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.registerPasswordHintsTitle,
            style: AppTypography.labelMedium.copyWith(color: AppColors.gray600),
          ),
          const SizedBox(height: 8),
          _buildRequirement(context.l10n.registerPasswordHintLength, hasLength),
          _buildRequirement(context.l10n.registerPasswordHintUppercase, hasUppercase),
          _buildRequirement(context.l10n.registerPasswordHintNumber, hasNumber),
        ],
      ),
    );
  }

  Widget _buildRequirement(String text, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle : Icons.circle_outlined,
            size: 16,
            color: met ? AppTheme.successColor : AppColors.gray400,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: AppTypography.bodySmall.copyWith(
              color: met ? AppTheme.successColor : AppColors.gray500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsentRow() {
    final linkStyle = const TextStyle(
      color: AppTheme.primaryColor,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
    final baseStyle =
        AppTypography.bodySmall.copyWith(color: AppColors.gray700, height: 1.4);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: _agreedToTerms,
            onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
            activeColor: AppTheme.primaryColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text.rich(
              TextSpan(
                style: baseStyle,
                children: [
                  TextSpan(text: context.l10n.registerAgreePrefix),
                  TextSpan(
                    text: context.l10n.registerTermsOfService,
                    style: linkStyle,
                    recognizer: _termsRecognizer,
                  ),
                  TextSpan(text: context.l10n.registerAgreeConjunction),
                  TextSpan(
                    text: context.l10n.registerPrivacyPolicy,
                    style: linkStyle,
                    recognizer: _privacyRecognizer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContinueButton() {
    final enabled = _agreedToTerms && !_checking;
    return AppButton(
      text: 'Continue',
      size: AppButtonSize.large,
      isFullWidth: true,
      isLoading: _checking,
      onPressed: enabled ? _handleContinue : null,
    );
  }

  Future<void> _handleContinue() async {
    if (!_agreedToTerms || _checking) return;
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    setState(() {
      _checking = true;
      _emailAvailabilityError = null;
    });

    try {
      final result =
          await ref.read(authAvailabilityServiceProvider).checkEmail(email);
      if (!mounted) return;

      if (result.success && result.data == false) {
        // Email is taken — block advancing and surface an inline error.
        setState(() {
          _emailAvailabilityError = context.l10n.registerEmailTaken;
        });
        return;
      }

      // Available (true) OR the check failed (fail-open): proceed. The final
      // register() call still enforces uniqueness server-side, so a
      // check-email outage never blocks signup.
      widget.data.email = email;
      widget.data.password = _passwordController.text;
      widget.onNext();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }
}
