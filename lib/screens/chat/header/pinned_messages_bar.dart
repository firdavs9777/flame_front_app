import 'package:flutter/material.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/services/chat_service.dart' show PinnedMessage;
import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';

/// Strip above the thread showing the most recently pinned message.
class PinnedMessagesBar extends StatelessWidget {
  const PinnedMessagesBar({
    super.key,
    required this.pinned,
    required this.onTap,
    required this.onUnpin,
  });

  final List<PinnedMessage> pinned;
  final void Function(String messageId) onTap;
  final void Function(String messageId) onUnpin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = pinned.last;

    return Material(
      color: context.fill,
      child: InkWell(
        onTap: () => onTap(latest.messageId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.push_pin, size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pinned.length == 1
                          ? context.l10n.chatPinnedOne
                          : context.l10n.chatPinnedCount(pinned.length),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      latest.content.isEmpty
                          ? context.l10n.chatAttachment
                          : latest.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: context.onSurface),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: context.l10n.chatUnpin,
                color: context.secondaryText,
                onPressed: () => onUnpin(latest.messageId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
