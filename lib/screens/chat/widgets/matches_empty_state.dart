import 'package:flutter/material.dart';
import 'package:flame/theme/app_tokens.dart';
import 'package:flame/core/i18n/build_context_ext.dart';

/// Shown in the Messages list when the user has no conversations yet.
///
/// It renders inside a `SliverFillRemaining` beneath the "New Matches" strip,
/// so the height it gets is whatever that strip leaves — as little as ~142px on
/// a phone, against roughly 155px of content. With the sliver's default
/// `hasScrollBody: true` the child is forced to exactly that extent, which
/// overflowed by 13px in production.
///
/// `mainAxisSize.min` keeps the column shrink-wrapped so it never demands more
/// than its content, and the caller pairs this with `hasScrollBody: false` so a
/// genuinely cramped viewport scrolls instead of clipping.
class MatchesEmptyState extends StatelessWidget {
  const MatchesEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 80, color: context.secondaryText),
            const SizedBox(height: 16),
            Text(
              context.l10n.chatNoMessagesTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: context.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.chatNoMessagesBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}
