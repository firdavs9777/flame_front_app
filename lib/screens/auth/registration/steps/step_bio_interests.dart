import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/core/interests/interest_catalogue.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/screens/auth/widgets/auth_snackbar.dart';

class StepBioInterests extends StatefulWidget {
  final RegistrationData data;
  final VoidCallback onNext;

  const StepBioInterests({
    super.key,
    required this.data,
    required this.onNext,
  });

  @override
  State<StepBioInterests> createState() => _StepBioInterestsState();
}

class _StepBioInterestsState extends State<StepBioInterests> {
  final _bioController = TextEditingController();
  final List<String> _selectedInterests = [];

  /// The shared catalogue, not a local copy.
  ///
  /// This list used to live here and a second, partly-different one lived in the
  /// filter sheet — which is how the sheet ended up offering an interest
  /// ('Hiking') that registration never let anyone pick.
  static const List<Interest> _availableInterests = kInterests;

  @override
  void initState() {
    super.initState();
    _bioController.text = widget.data.bio;
    _selectedInterests.addAll(widget.data.interests);
  }

  @override
  void dispose() {
    _bioController.dispose();
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bio Section
            Text(
              context.l10n.registerBioSectionTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.registerBioSubtitle,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 12),
            _buildBioField()
                .animate()
                .fadeIn(delay: 100.ms, duration: 400.ms),

            const SizedBox(height: 32),

            // Interests Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.l10n.registerInterestsSectionTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _selectedInterests.isNotEmpty
                        ? AppTheme.successColor.withValues(alpha: 0.1)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    context.l10n.registerInterestsCounter(_selectedInterests.length),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _selectedInterests.isNotEmpty
                          ? AppTheme.successColor
                          : Colors.grey[500],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.registerInterestsSubtitle,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 16),
            _buildInterestsGrid()
                .animate()
                .fadeIn(delay: 200.ms, duration: 400.ms),

            const SizedBox(height: 32),

            // Continue Button
            _buildContinueButton()
                .animate()
                .fadeIn(delay: 300.ms, duration: 400.ms)
                .slideY(begin: 0.2, end: 0, delay: 300.ms, duration: 400.ms),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, duration: 400.ms),
    );
  }

  Widget _buildBioField() {
    return AppInput(
      controller: _bioController,
      hint: context.l10n.registerBioHint,
      maxLines: 4,
      minLines: 4,
      maxLength: 300,
    );
  }

  Widget _buildInterestsGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _availableInterests.map((interest) {
        final isSelected = _selectedInterests.contains(interest.token);

        return GestureDetector(
          onTap: () => _toggleInterest(interest.token),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? interest.color.withValues(alpha: 0.15) : Colors.grey[50],
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isSelected ? interest.color : Colors.grey[200]!,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  interest.icon,
                  size: 18,
                  color: isSelected ? interest.color : Colors.grey[500],
                ),
                const SizedBox(width: 6),
                Text(
                  interest.label(context.l10n),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? interest.color : AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _toggleInterest(String interest) {
    setState(() {
      if (_selectedInterests.contains(interest)) {
        _selectedInterests.remove(interest);
      } else if (_selectedInterests.length < 5) {
        _selectedInterests.add(interest);
      } else {
        showAuthSnackBar(
          context,
          message: context.l10n.registerInterestsMax,
          type: AuthSnackBarType.warning,
        );
      }
    });
  }

  Widget _buildContinueButton() {
    final enabled = canContinue(_selectedInterests.length);
    return Column(
      children: [
        AppButton(
          text: context.l10n.registerContinue,
          size: AppButtonSize.large,
          isFullWidth: true,
          onPressed: enabled ? () => _handleContinue(skipBio: false) : null,
        ),
        const SizedBox(height: 8),
        AppButton(
          text: context.l10n.registerSkipForNow,
          variant: AppButtonVariant.ghost,
          isFullWidth: true,
          onPressed: enabled ? () => _handleContinue(skipBio: true) : null,
        ),
      ],
    );
  }

  void _handleContinue({required bool skipBio}) {
    if (!canContinue(_selectedInterests.length)) {
      showAuthSnackBar(
        context,
        message: context.l10n.registerInterestsMin,
        type: AuthSnackBarType.error,
      );
      return;
    }

    // Bio is optional; "Skip for now" advances without it.
    widget.data.bio = skipBio ? '' : _bioController.text.trim();
    widget.data.interests = List.from(_selectedInterests);
    widget.onNext();
  }
}

/// Whether the bio/interests step can advance. Backend `registerSchema`
/// requires at least one interest; bio is optional. Extracted so the
/// enable-logic is unit-testable independent of the widget.
bool canContinue(int selectedInterestCount) => selectedInterestCount >= 1;

