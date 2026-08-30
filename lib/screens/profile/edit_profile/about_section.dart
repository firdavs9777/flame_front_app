import 'package:flutter/material.dart';
import 'package:flame/core/date/age.dart';

import 'package:flame/models/models.dart';
import 'package:flame/screens/profile/edit_profile/edit_profile_screen.dart';
import 'package:flame/screens/profile/edit_profile/section_chrome.dart';
import 'package:flame/theme/app_tokens.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/widgets/bio_suggestions.dart';

class AboutSection extends StatefulWidget {
  final User user;
  final AboutSave onSave;

  const AboutSection({required this.user, required this.onSave});

  @override
  State<AboutSection> createState() => AboutSectionState();
}

class AboutSectionState extends State<AboutSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;

  /// The age as it stands, held as a number rather than as text.
  ///
  /// It used to be a `TextEditingController` the user typed into, which meant
  /// "17" and "abc" were both reachable and had to be rejected afterwards. The
  /// date picker's bounds make an invalid age unreachable instead.
  late int _age;
  bool _isSaving = false;

  // The route's own bounds: `age: z.number().int().min(18).max(100)`
  // (flame/routes/users.js:17). They belong to the picker now, not to a
  // validator, so an ineligible date simply cannot be selected.
  static const _minimumAge = 18;
  static const _maximumAge = 100;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _bioController = TextEditingController(text: widget.user.bio);
    _age = widget.user.age;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  /// Opens the birthday picker, bounded so only an eligible date can be chosen.
  ///
  /// The date itself is not stored: the server keeps an integer age and has no
  /// birthdate field, so this derives the age and sends that. Reopening the
  /// screen therefore shows a date derived from the age, not the real birthday
  /// — a known trade, documented in `lib/core/date/age.dart`.
  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: birthDateForAge(_age, now: now),
      firstDate: earliestBirthDateFor(_maximumAge, now: now),
      lastDate: latestBirthDateFor(_minimumAge, now: now),
      helpText: context.l10n.profileSelectBirthDate,
    );
    if (picked == null) return;
    setState(() => _age = ageOn(picked, now: DateTime.now()));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final ok = await widget.onSave(
      name: _nameController.text.trim(),
      age: _age,
      bio: _bioController.text,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? context.l10n.profileAboutUpdated
            : context.l10n.profileSaveFailed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          fieldLabel(context, context.l10n.profileNameLabel),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('about_name_field'),
            controller: _nameController,
            decoration: fieldDecoration(context, context.l10n.profileNameHint),
            // Both bounds are the route's own: User.name is minlength 2,
            // maxlength 50. Only the floor was checked, so a 60-character
            // name went out and came back as a bare "Could not save".
            validator: (value) {
              final name = (value ?? '').trim();
              if (name.length < 2) {
                return context.l10n.authNameTooShort;
              }
              if (name.length > 50) {
                return context.l10n.profileNameTooLongWithCount(name.length);
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          fieldLabel(context, context.l10n.profileAgeLabel),
          const SizedBox(height: 8),
          // A picker rather than a number field: the bounds below make an
          // ineligible age unreachable, so there is no error state to report.
          InkWell(
            key: const Key('about_age_picker'),
            onTap: _pickBirthDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: fieldDecoration(context, context.l10n.profileAgeHint),
              child: Row(
                children: [
                  Icon(Icons.cake_outlined, size: 20, color: context.secondaryText),
                  const SizedBox(width: 12),
                  Text(
                    '$_age',
                    key: const Key('about_age_value'),
                    style: TextStyle(fontSize: 16, color: context.onSurface),
                  ),
                  const Spacer(),
                  Icon(Icons.calendar_today_outlined,
                      size: 18, color: context.secondaryText),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          fieldLabel(context, context.l10n.profileAboutMe),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('about_bio_field'),
            controller: _bioController,
            maxLines: 4,
            maxLength: 500,
            decoration:
                fieldDecoration(context, context.l10n.profileBioHint),
          ),
          // Interests are edited in their own section, so these are the saved
          // ones — which is the right input anyway: a draft built from tags the
          // user has not saved yet would describe a profile nobody can see.
          BioSuggestions(
            interests: widget.user.interests,
            onUse: (bio) => setState(() {
              _bioController.text = bio;
              // Land the caret at the end so the first keystroke edits the
              // draft rather than replacing it.
              _bioController.selection = TextSelection.collapsed(
                offset: bio.length,
              );
            }),
          ),
          const SizedBox(height: 8),
          SaveButton(
            buttonKey: const Key('about_save_button'),
            isSaving: _isSaving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// Looking-for gender and interest tags, saved together — the pair the
/// original form always submitted as one unit.
///
/// This section has no `Form` because it has no text fields, which is how it
/// ended up as the one section in a form-validation task with no validation at
/// all: the route requires 1 to 10 interests
/// (`interests: Field(min_length=1, max_length=10)`), while the picker offers
/// 16 chips with no floor and no cap. Deselecting your last interest, or
/// picking an eleventh, produced a bare "Could not save — try again" with no
/// hint as to which. [_boundsError] is checked before [onSave] is called, and
/// names the bound that was hit.
