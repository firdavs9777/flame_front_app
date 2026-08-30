import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/models/user.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/core/validation/auth_validators.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/widgets/kit/kit.dart';

class StepProfileInfo extends StatefulWidget {
  final RegistrationData data;
  final VoidCallback onNext;

  const StepProfileInfo({
    super.key,
    required this.data,
    required this.onNext,
  });

  @override
  State<StepProfileInfo> createState() => _StepProfileInfoState();
}

class _StepProfileInfoState extends State<StepProfileInfo> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  late int _selectedAge;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.data.name;
    _selectedAge = widget.data.age;
  }

  @override
  void dispose() {
    _nameController.dispose();
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
              // Name Field
              _buildNameField()
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 400.ms)
                  .slideX(begin: 0.1, end: 0, delay: 100.ms, duration: 400.ms),

              const SizedBox(height: 24),

              // Birthday/Age
              _buildLabel(context.l10n.registerAgeLabel),
              const SizedBox(height: 8),
              _buildAgeSelector()
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 400.ms)
                  .slideX(begin: 0.1, end: 0, delay: 200.ms, duration: 400.ms),

              // Gender moved to the Looking For step. It is half of one
              // matching decision — "I am X, show me Y" — and asking it here,
              // as small chips, gave it a fraction of the weight the other half
              // got a screen later.

              const SizedBox(height: 32),

              // Continue Button
              _buildContinueButton()
                  .animate()
                  .fadeIn(delay: 400.ms, duration: 400.ms)
                  .slideY(begin: 0.2, end: 0, delay: 400.ms, duration: 400.ms),
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

  Widget _buildNameField() {
    final validators = AuthValidators(context.l10n);
    return AppInput(
      controller: _nameController,
      label: context.l10n.registerFirstNameLabel,
      hint: context.l10n.registerFirstNameHint,
      prefixIcon: Icons.person_outline_rounded,
      textInputAction: TextInputAction.next,
      validator: validators.name,
    );
  }

  Widget _buildAgeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.cake_outlined, color: Colors.grey[400]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.registerAgeYearsOld(_selectedAge),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.primaryColor,
                    inactiveTrackColor: Colors.grey[300],
                    thumbColor: AppTheme.primaryColor,
                    overlayColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _selectedAge.toDouble(),
                    min: 18,
                    max: 100,
                    divisions: 82,
                    onChanged: (value) {
                      setState(() => _selectedAge = value.round());
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Self-description phrasing ("I am a...") for the gender chips — distinct
  /// from [Gender.displayName] (used for third-person contexts elsewhere) and
  /// from the looking-for chips' "Men"/"Women" phrasing, which reads wrong
  /// here ("I am a... Men").
  Widget _buildContinueButton() {
    return AppButton(
      text: context.l10n.registerContinue,
      size: AppButtonSize.large,
      isFullWidth: true,
      onPressed: _handleContinue,
    );
  }

  void _handleContinue() {
    if (_formKey.currentState!.validate()) {
      widget.data.name = _nameController.text.trim();
      widget.data.age = _selectedAge;
      widget.onNext();
    }
  }
}
