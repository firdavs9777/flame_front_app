import 'package:flutter/material.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/interests/interest_catalogue.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/profile/edit_profile/edit_profile_screen.dart';
import 'package:flame/screens/profile/edit_profile/section_chrome.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';

class InterestsSection extends StatefulWidget {
  final User user;
  final InterestsSave onSave;

  const InterestsSection({required this.user, required this.onSave});

  @override
  State<InterestsSection> createState() => InterestsSectionState();
}

class InterestsSectionState extends State<InterestsSection> {
  /// The shared catalogue, not a third local copy.
  ///
  /// This was the third hardcoded interest list in the app, and the most
  /// consequential: it writes `user.interests`, so anything it offered that the
  /// discovery filter did not know about could never be matched, and anything it
  /// omitted could never be picked.
  static const _allInterests = kInterests;

  /// The route's own bounds on `interests`.
  static const _minInterests = 1;
  static const _maxInterests = 10;

  late Gender? _lookingFor;
  late List<String> _selectedInterests;
  String? _boundsError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _lookingFor = widget.user.lookingFor;
    _selectedInterests = List<String>.from(widget.user.interests);
  }

  /// Names the bound that was hit, or null when the selection is savable.
  String? _validate() {
    final count = _selectedInterests.length;
    if (count < _minInterests) {
      return 'Pick at least $_minInterests interest';
    }
    if (count > _maxInterests) {
      return 'Pick at most $_maxInterests interests — $count are selected';
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      setState(() => _boundsError = error);
      return;
    }

    setState(() {
      _boundsError = null;
      _isSaving = true;
    });
    final ok = await widget.onSave(
      lookingFor: _lookingFor,
      interests: _selectedInterests,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Interests updated' : 'Could not save — try again'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fieldLabel(context, 'Looking For'),
        const SizedBox(height: 12),
        _buildGenderSelector(context),
        const SizedBox(height: 20),
        fieldLabel(context, 'Interests'),
        const SizedBox(height: 12),
        _buildInterestsSelector(context),
        if (_boundsError != null) ...[
          const SizedBox(height: 8),
          Text(
            _boundsError!,
            key: const Key('interests_bounds_error'),
            style: TextStyle(color: AppTheme.errorColor, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        SaveButton(
          buttonKey: const Key('interests_save_button'),
          isSaving: _isSaving,
          onPressed: _save,
        ),
      ],
    );
  }

  Widget _buildGenderSelector(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: Gender.values.map((gender) {
        final isSelected = _lookingFor == gender;
        return GestureDetector(
          onTap: () => setState(() => _lookingFor = gender),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryColor : context.fill,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              gender.displayName,
              style: TextStyle(
                color: isSelected ? context.onPrimary : context.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInterestsSelector(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _allInterests.map((interest) {
        final isSelected = _selectedInterests.contains(interest.token);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedInterests.remove(interest.token);
              } else {
                _selectedInterests.add(interest.token);
              }
              // Re-evaluate a message already on screen so it tracks the
              // selection instead of going stale, but don't surface one before
              // the user has asked to save.
              if (_boundsError != null) _boundsError = _validate();
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryColor.withValues(alpha: 0.1)
                  : context.fill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? AppTheme.primaryColor : context.divider,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Text(
              interest.label(context.l10n),
              style: TextStyle(
                color: isSelected ? AppTheme.primaryColor : context.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Discovery preferences: min age, max age, max distance, and "Show online
/// status" — deliberately NOT "Show distance". `showDistance` is stored and
/// saveable server-side, but `discoveryService.toDiscoverUser` hardcodes
/// `distance: 0`, so a toggle here would govern a number that always reads
/// zero. That is the dead-button pattern this codebase has already spent
/// effort removing twice; it becomes real the day distance itself does.
///
/// Validates min age <= max age before calling [onSave], matching the
/// route's own refine — catching it here saves a round trip and a 422.
