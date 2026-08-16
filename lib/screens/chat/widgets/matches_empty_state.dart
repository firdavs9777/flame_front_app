import 'package:flutter/material.dart';

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
            Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Match with someone to start chatting!',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}
