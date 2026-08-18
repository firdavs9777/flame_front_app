import 'package:flutter/material.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/image/avatar_provider.dart';
import 'package:flame/theme/app_tokens.dart';

/// Shown for a conversation that has loaded and genuinely has no messages.
///
/// Reachable only from that state — never from a failed load, which is what
/// [ChatErrorWidget] is for.
class ConversationEmptyState extends StatelessWidget {
  const ConversationEmptyState({
    super.key,
    required this.otherUserName,
    required this.otherUserPhoto,
  });

  final String otherUserName;
  final String otherUserPhoto;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: context.fill,
              backgroundImage: avatarProvider(
                otherUserPhoto,
                diameter: 100,
                devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.chatMatchedWith(otherUserName),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.chatSendFirstMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}
