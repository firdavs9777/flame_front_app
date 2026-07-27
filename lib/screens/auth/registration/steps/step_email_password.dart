import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/providers/auth_availability_provider.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/screens/auth/registration/legal_document_sheet.dart';
import 'package:flame/core/i18n/build_context_ext.dart';

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
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
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
      child: Container(
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
              _buildLabel('Email Address'),
              const SizedBox(height: 8),
              _buildEmailField()
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 400.ms)
                  .slideX(begin: 0.1, end: 0, delay: 100.ms, duration: 400.ms),

              if (_emailAvailabilityError != null) _buildEmailAvailabilityError(),

              const SizedBox(height: 24),

              // Password Field
              _buildLabel('Password'),
              const SizedBox(height: 8),
              _buildPasswordField()
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 400.ms)
                  .slideX(begin: 0.1, end: 0, delay: 200.ms, duration: 400.ms),

              const SizedBox(height: 24),

              // Confirm Password Field
              _buildLabel('Confirm Password'),
              const SizedBox(height: 8),
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

  Widget _buildLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      style: const TextStyle(fontSize: 16),
      onChanged: (_) {
        if (_emailAvailabilityError != null) {
          setState(() => _emailAvailabilityError = null);
        }
      },
      decoration: InputDecoration(
        hintText: 'you@example.com',
        hintStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(Icons.email_outlined, color: Colors.grey[400]),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.errorColor, width: 1),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your email';
        }
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
          return 'Please enter a valid email';
        }
        return null;
      },
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
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppTheme.primaryColor,
              ),
              child: const Text(
                'Log in instead',
                style: TextStyle(
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
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: 'Create a strong password',
        hintStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(Icons.lock_outline_rounded, color: Colors.grey[400]),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          icon: Icon(
            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.grey[400],
          ),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.errorColor, width: 1),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter a password';
        }
        if (value.length < 8) {
          return 'Password must be at least 8 characters';
        }
        return null;
      },
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirmPassword,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        hintText: 'Confirm your password',
        hintStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: Icon(Icons.lock_outline_rounded, color: Colors.grey[400]),
        suffixIcon: IconButton(
          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
          icon: Icon(
            _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: Colors.grey[400],
          ),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppTheme.errorColor, width: 1),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please confirm your password';
        }
        if (value != _passwordController.text) {
          return 'Passwords do not match';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordRequirements() {
    final password = _passwordController.text;
    final hasLength = password.length >= 8;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasNumber = password.contains(RegExp(r'[0-9]'));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Password must contain:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          _buildRequirement('At least 8 characters', hasLength),
          _buildRequirement('One uppercase letter', hasUppercase),
          _buildRequirement('One number', hasNumber),
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
            color: met ? AppTheme.successColor : Colors.grey[400],
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: met ? AppTheme.successColor : Colors.grey[500],
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
    final baseStyle = TextStyle(fontSize: 13, color: Colors.grey[700], height: 1.4);
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
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: enabled ? _handleContinue : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.primaryColor.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _checking
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Continue',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
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
          _emailAvailabilityError = 'That email is already registered';
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
