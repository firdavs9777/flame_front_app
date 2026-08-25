import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/models/user.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/screens/auth/widgets/auth_snackbar.dart';

class StepLookingFor extends StatefulWidget {
  final RegistrationData data;
  final VoidCallback onNext;

  const StepLookingFor({
    super.key,
    required this.data,
    required this.onNext,
  });

  @override
  State<StepLookingFor> createState() => _StepLookingForState();
}

class _StepLookingForState extends State<StepLookingFor> {
  Gender? _selectedPreference;

  @override
  void initState() {
    super.initState();
    _selectedPreference = widget.data.lookingFor == Gender.other ? null : widget.data.lookingFor;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.registerShowMeTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.registerSelectWhoToSee,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 24),

            // Gender preference options
            ..._buildPreferenceOptions(),

            const SizedBox(height: 32),

            // Continue Button
            _buildContinueButton()
                .animate()
                .fadeIn(delay: 500.ms, duration: 400.ms)
                .slideY(begin: 0.2, end: 0, delay: 500.ms, duration: 400.ms),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, duration: 400.ms),
    );
  }

  List<Widget> _buildPreferenceOptions() {
    final options = [
      _PreferenceOption(
        gender: Gender.male,
        title: context.l10n.registerGenderMen,
        icon: Icons.male_rounded,
        color: const Color(0xFF5B9BD5),
      ),
      _PreferenceOption(
        gender: Gender.female,
        title: context.l10n.registerGenderWomen,
        icon: Icons.female_rounded,
        color: const Color(0xFFFF69B4),
      ),
      _PreferenceOption(
        gender: Gender.nonBinary,
        title: context.l10n.registerGenderNonBinary,
        icon: Icons.transgender_rounded,
        color: const Color(0xFF9B59B6),
      ),
      _PreferenceOption(
        gender: Gender.other,
        title: context.l10n.registerGenderEveryone,
        icon: Icons.people_rounded,
        color: AppTheme.primaryColor,
      ),
    ];

    return options.asMap().entries.map((entry) {
      final index = entry.key;
      final option = entry.value;
      final isSelected = _selectedPreference == option.gender;

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: GestureDetector(
          onTap: () => setState(() => _selectedPreference = option.gender),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isSelected ? option.color.withValues(alpha: 0.1) : Colors.grey[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? option.color : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected ? option.color : Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    option.icon,
                    color: isSelected ? Colors.white : Colors.grey[500],
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    option.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? option.color : AppTheme.textPrimary,
                    ),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? option.color : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? option.color : Colors.grey[300]!,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        )
                      : null,
                ),
              ],
            ),
          ),
        ).animate()
            .fadeIn(delay: Duration(milliseconds: 100 + (index * 100)), duration: 400.ms)
            .slideX(begin: 0.1, end: 0, delay: Duration(milliseconds: 100 + (index * 100)), duration: 400.ms),
      );
    }).toList();
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
    if (_selectedPreference == null) {
      showAuthSnackBar(
        context,
        message: context.l10n.registerLookingForRequired,
        type: AuthSnackBarType.error,
      );
      return;
    }

    widget.data.lookingFor = _selectedPreference!;
    widget.onNext();
  }
}

class _PreferenceOption {
  final Gender gender;
  final String title;
  final IconData icon;
  final Color color;

  const _PreferenceOption({
    required this.gender,
    required this.title,
    required this.icon,
    required this.color,
  });
}
