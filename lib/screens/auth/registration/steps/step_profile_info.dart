import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/models/user.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/core/validation/auth_validators.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/screens/auth/widgets/auth_snackbar.dart';

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
  Gender? _selectedGender;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.data.name;
    _selectedAge = widget.data.age;
    _selectedGender = widget.data.gender == Gender.other ? null : widget.data.gender;
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

              const SizedBox(height: 24),

              // Gender
              _buildLabel(context.l10n.registerGenderQuestionLabel),
              const SizedBox(height: 12),
              _buildGenderSelector()
                  .animate()
                  .fadeIn(delay: 300.ms, duration: 400.ms)
                  .slideX(begin: 0.1, end: 0, delay: 300.ms, duration: 400.ms),

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

  Widget _buildGenderSelector() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: Gender.values.where((g) => g != Gender.other).map((gender) {
        final isSelected = _selectedGender == gender;
        return GestureDetector(
          onTap: () => setState(() => _selectedGender = gender),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryColor : Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppTheme.primaryColor : Colors.grey[200]!,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getGenderIcon(gender),
                  color: isSelected ? Colors.white : Colors.grey[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _genderSelfLabel(context, gender),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _getGenderIcon(Gender gender) {
    switch (gender) {
      case Gender.male:
        return Icons.male_rounded;
      case Gender.female:
        return Icons.female_rounded;
      case Gender.nonBinary:
        return Icons.transgender_rounded;
      default:
        return Icons.person_outline_rounded;
    }
  }

  /// Self-description phrasing ("I am a...") for the gender chips — distinct
  /// from [Gender.displayName] (used for third-person contexts elsewhere) and
  /// from the looking-for chips' "Men"/"Women" phrasing, which reads wrong
  /// here ("I am a... Men").
  String _genderSelfLabel(BuildContext context, Gender gender) {
    switch (gender) {
      case Gender.male:
        return context.l10n.registerGenderSelfMale;
      case Gender.female:
        return context.l10n.registerGenderSelfFemale;
      case Gender.nonBinary:
        return context.l10n.registerGenderSelfNonBinary;
      case Gender.other:
        return gender.displayName;
    }
  }

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
      if (_selectedGender == null) {
        showAuthSnackBar(
          context,
          message: context.l10n.registerGenderRequired,
          type: AuthSnackBarType.error,
        );
        return;
      }

      widget.data.name = _nameController.text.trim();
      widget.data.age = _selectedAge;
      widget.data.gender = _selectedGender!;
      widget.onNext();
    }
  }
}
