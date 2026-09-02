import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/languages/language_fallback.dart';
import 'package:flame/core/languages/language_label.dart';
import 'package:flame/core/navigation/app_routes.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/languages_provider.dart';
import 'package:flame/screens/profile/edit_profile/edit_profile_screen.dart';
import 'package:flame/screens/profile/edit_profile/section_chrome.dart';

/// Declaring what you speak and what you are learning, from the profile.
///
/// Registration step 4 was the only way in, which meant every account that
/// existed before this release could never declare a language at all: they
/// stayed on the neutral language score forever and the "Speaks / Learning"
/// lines rendered nothing for them. The premise of the product was reachable
/// only by people who did not have an account yet.
///
/// Modelled on [InterestsSection] next door — local edits, one Save button,
/// one snackbar — so the two read as the same screen rather than as two
/// different ideas of what a section is.
class LanguagesSection extends ConsumerStatefulWidget {
  final User user;
  final LanguagesSave onSave;

  const LanguagesSection({super.key, required this.user, required this.onSave});

  @override
  ConsumerState<LanguagesSection> createState() => LanguagesSectionState();
}

class LanguagesSectionState extends ConsumerState<LanguagesSection> {
  /// The backend validator rejects a fourth code outright, so the picker
  /// caps the selection rather than letting the save 422. Same number
  /// registration step 4 passes.
  static const int _maxLanguages = 3;

  late List<String> _spoken;
  late List<String> _learning;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _spoken = List<String>.from(widget.user.languagesSpoken);
    _learning = List<String>.from(widget.user.languagesLearning);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    final ok = await widget.onSave(
      languagesSpoken: _spoken,
      languagesLearning: _learning,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? context.l10n.profileLanguagesUpdated
            : context.l10n.profileSaveFailed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _languageRow(
          rowKey: const Key('profile_languages_spoken'),
          label: context.l10n.languagesSpokenLabel,
          codes: _spoken,
          onChanged: (picked) => setState(() => _spoken = picked),
        ),
        _languageRow(
          rowKey: const Key('profile_languages_learning'),
          label: context.l10n.languagesLearningLabel,
          codes: _learning,
          onChanged: (picked) => setState(() => _learning = picked),
        ),
        const SizedBox(height: 12),
        SaveButton(
          buttonKey: const Key('languages_save_button'),
          isSaving: _isSaving,
          onPressed: _save,
        ),
      ],
    );
  }

  /// One row, opening the shared picker BY NAME — the same call registration
  /// step 4 makes, so there is still exactly one language picker in the app.
  Widget _languageRow({
    required Key rowKey,
    required String label,
    required List<String> codes,
    required ValueChanged<List<String>> onChanged,
  }) {
    final catalog =
        ref.watch(languageCatalogProvider).valueOrNull ?? kLanguageFallback;
    final summary = codes.isEmpty
        ? context.l10n.languagesNoneSelected
        : codes.map((c) => languageLabel(c, catalog)).join(', ');

    return ListTile(
      key: rowKey,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(summary),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).pushNamed(
        AppRoutes.languagePicker,
        arguments: LanguagePickerArgs(
          initialSelection: codes,
          maxSelection: _maxLanguages,
          onDone: (picked) {
            Navigator.of(context).pop();
            onChanged(picked);
          },
        ),
      ),
    );
  }
}
