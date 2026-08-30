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
  Gender? _selectedGender;
  Gender? _selectedPreference;

  @override
  void initState() {
    super.initState();
    // Gender lives here now. It is the other half of one matching decision —
    // "I am X, show me Y" — and it used to be asked a screen earlier as small
    // chips, which gave it a fraction of the weight its counterpart got here.
    _selectedGender =
        widget.data.gender == Gender.other ? null : widget.data.gender;
    _selectedPreference = widget.data.lookingFor == Gender.other ? null : widget.data.lookingFor;
  }

  /// The three a person picks for themselves. Deliberately not the same list
  /// as the preference options below, which include "Everyone" — an answer to
  /// who you want to see, never to who you are.
  static const _identities = [Gender.male, Gender.female, Gender.nonBinary];

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
            _sectionTitle(context.l10n.registerGenderQuestionLabel),
            const SizedBox(height: 12),
            _buildIdentityRow(),

            const SizedBox(height: 28),
            Divider(color: Colors.grey[200], height: 1),
            const SizedBox(height: 28),

            _sectionTitle(context.l10n.registerShowMeTitle),
            const SizedBox(height: 8),
            Text(
              context.l10n.registerSelectWhoToSee,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 20),

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

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      );

  /// Three compact cards in a row, colour-coded to match the preference rows
  /// below so the two questions visibly belong to each other. Compact rather
  /// than full-width: it is one tap on a shorter list, and giving it the same
  /// height as the four rows underneath would push the button off-screen.
  Widget _buildIdentityRow() {
    return Row(
      children: [
        for (final gender in _identities) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedGender = gender),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                decoration: BoxDecoration(
                  color: _selectedGender == gender
                      ? _identityColor(gender).withValues(alpha: 0.1)
                      : Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _selectedGender == gender
                        ? _identityColor(gender)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _identityIcon(gender),
                      size: 26,
                      color: _selectedGender == gender
                          ? _identityColor(gender)
                          : Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _identityLabel(gender),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _selectedGender == gender
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: _selectedGender == gender
                            ? AppTheme.textPrimary
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (gender != _identities.last) const SizedBox(width: 12),
        ],
      ],
    );
  }

  // Same three colours the preference rows use, so "I am a woman" and
  // "show me women" read as the same category rather than two palettes.
  Color _identityColor(Gender g) => switch (g) {
        Gender.male => const Color(0xFF5B9BD5),
        Gender.female => const Color(0xFFFF69B4),
        _ => const Color(0xFF9B59B6),
      };

  IconData _identityIcon(Gender g) => switch (g) {
        Gender.male => Icons.male_rounded,
        Gender.female => Icons.female_rounded,
        _ => Icons.transgender_rounded,
      };

  String _identityLabel(Gender g) => switch (g) {
        Gender.male => context.l10n.registerGenderSelfMale,
        Gender.female => context.l10n.registerGenderSelfFemale,
        _ => context.l10n.registerGenderSelfNonBinary,
      };

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
    if (_selectedGender == null) {
      showAuthSnackBar(
        context,
        message: context.l10n.registerGenderRequired,
        type: AuthSnackBarType.error,
      );
      return;
    }
    if (_selectedPreference == null) {
      showAuthSnackBar(
        context,
        message: context.l10n.registerLookingForRequired,
        type: AuthSnackBarType.error,
      );
      return;
    }

    widget.data.gender = _selectedGender!;
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
