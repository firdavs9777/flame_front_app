import 'package:flutter/material.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/theme/app_tokens.dart';

/// A failed load, with a way out of it.
///
/// Its existence is the point. A failure used to leave the message list empty,
/// which rendered the say-hello prompt and invited the user to greet a thread
/// that had not loaded — the same collapse of loading into error the profile
/// follow-ups recorded in `settings_screen`.
class ChatErrorWidget extends StatelessWidget {
  const ChatErrorWidget({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: context.secondaryText),
            const SizedBox(height: 16),
            Text(
              context.l10n.chatLoadFailed,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.secondaryText),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRetry,
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
