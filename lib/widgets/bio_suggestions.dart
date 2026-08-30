import 'package:flutter/material.dart';

import 'package:flame/config/env.dart';
import 'package:flame/core/bio/bio_templates.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';

/// Offers ready-made bios under a bio field, and fills the field with whichever
/// one the user picks.
///
/// Shared by registration and edit-profile because the field is the same field
/// and the hard part is the same in both: a blank box with no idea what belongs
/// in it.
///
/// The drafts are built on the device from the user's own interests — see
/// [bioSuggestions]. Nothing is written without a tap, and what lands in the
/// field is ordinary editable text, so the last word is always the user's.
class BioSuggestions extends StatefulWidget {
  const BioSuggestions({
    super.key,
    required this.interests,
    required this.onUse,
  });

  /// The tokens the drafts are built from. Empty is a real state, not an error:
  /// on the registration step the bio field sits above the interest picker, so
  /// the button is reachable before anything is selected.
  final List<String> interests;

  /// Called with the chosen draft. The caller owns the controller.
  final ValueChanged<String> onUse;

  @override
  State<BioSuggestions> createState() => _BioSuggestionsState();
}

class _BioSuggestionsState extends State<BioSuggestions> {
  List<String> _suggestions = const [];
  bool _needsInterests = false;

  void _draft() {
    final drafts = bioSuggestions(widget.interests, context.l10n);
    setState(() {
      _suggestions = drafts;
      _needsInterests = drafts.isEmpty;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!EnvConfig.current.aiBioEnabled) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('bio_suggest_button'),
            onPressed: _draft,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: Text(context.l10n.bioSuggestButton),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.primaryColor,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
        if (_needsInterests) ...[
          const SizedBox(height: 4),
          Text(
            context.l10n.bioSuggestNeedsInterests,
            key: const Key('bio_suggest_error'),
            style: TextStyle(fontSize: 12, color: AppTheme.errorColor),
          ),
        ],
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (var i = 0; i < _suggestions.length; i++) ...[
            _buildCard(context, _suggestions[i], i),
            const SizedBox(height: 8),
          ],
          Text(
            context.l10n.bioSuggestDisclaimer,
            style: TextStyle(fontSize: 11, color: context.secondaryText),
          ),
        ],
      ],
    );
  }

  Widget _buildCard(BuildContext context, String suggestion, int index) {
    return InkWell(
      key: Key('bio_suggestion_$index'),
      onTap: () => widget.onUse(suggestion),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
        ),
        child: Text(
          suggestion,
          style: TextStyle(fontSize: 14, height: 1.4, color: context.onSurface),
        ),
      ),
    );
  }
}
