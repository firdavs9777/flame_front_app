import 'package:flutter/material.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/theme/app_tokens.dart';

/// The three things an empty-looking deck can mean.
///
/// One shared string used to guess at all of them: "Check back later or adjust
/// your filters" was shown for an empty deck whether the filters were the cause
/// or not, and for a failed fetch, which is neither.

/// Filters matched nobody. Actionable, so it offers a way out.
class DeckEmptyForFilters extends StatelessWidget {
  const DeckEmptyForFilters({super.key, required this.onRelaxFilters});

  final VoidCallback onRelaxFilters;

  @override
  Widget build(BuildContext context) {
    return _DeckState(
      icon: Icons.filter_alt_off_outlined,
      title: context.l10n.deckNoMatches,
      actionLabel: context.l10n.deckRelaxFilters,
      onAction: onRelaxFilters,
    );
  }
}

/// The deck is genuinely exhausted. Not actionable — nothing the user changes
/// will conjure more people — so the action is only a refresh.
class DeckSeenEveryone extends StatelessWidget {
  const DeckSeenEveryone({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _DeckState(
      icon: Icons.people_outline,
      title: context.l10n.deckSeenEveryone,
      actionLabel: context.l10n.deckRefresh,
      onAction: onRefresh,
    );
  }
}

/// The fetch failed. Must never render as either of the other two.
class DeckError extends StatelessWidget {
  const DeckError({super.key, required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _DeckState(
      icon: Icons.cloud_off_outlined,
      title: context.l10n.deckLoadFailed,
      detail: error,
      actionLabel: context.l10n.retry,
      onAction: onRetry,
    );
  }
}

class _DeckState extends StatelessWidget {
  const _DeckState({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    // No fixed-height box anywhere: a large system font must wrap, not clip.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: context.secondaryText),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: context.onSurface,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: context.secondaryText),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
