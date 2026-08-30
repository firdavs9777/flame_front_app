import 'package:flutter/material.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/image/avatar_provider.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/chat/state/thread_presence_provider.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';

/// The open conversation's header: partner avatar with a presence dot, their
/// name, and either "typing…" or their last-active line.
class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({
    super.key,
    required this.otherUser,
    required this.presence,
    required this.isMuted,
    required this.onToggleMute,
    required this.onOpenProfile,
    required this.onReport,
    required this.onBlock,
  });

  final User otherUser;
  final ThreadPresenceState presence;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final VoidCallback onOpenProfile;

  /// Reporting and blocking have to be reachable from the conversation itself.
  /// They lived only behind the partner's profile screen, which is two taps
  /// away and the last place someone looks when a chat turns abusive.
  final VoidCallback onReport;
  final VoidCallback onBlock;

  static const double _avatarDiameter = 40;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final isTyping = presence.isOtherTyping;

    return AppBar(
      titleSpacing: 0,
      title: GestureDetector(
        onTap: onOpenProfile,
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: _avatarDiameter / 2,
                  backgroundColor: context.fill,
                  backgroundImage: avatarProvider(
                    otherUser.primaryPhoto,
                    diameter: _avatarDiameter,
                    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                  ),
                ),
                if (presence.isOtherOnline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppTheme.successColor,
                        shape: BoxShape.circle,
                        // The ring reads as a cut-out from whatever is behind the
                        // dot, so it has to follow the surface into dark mode.
                        border: Border.all(color: context.surface, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    otherUser.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.onSurface,
                    ),
                  ),
                  Text(
                    isTyping ? context.l10n.chatTyping : otherUser.lastActiveText,
                    style: TextStyle(
                      fontSize: 12,
                      color: isTyping
                          ? AppTheme.primaryColor
                          : context.secondaryText,
                      fontWeight:
                          isTyping ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        // The videocam button that used to sit here did nothing — there is no
        // calling feature anywhere in the app. A control that cannot work is
        // worse than a missing one.
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'mute':
                onToggleMute();
              case 'profile':
                onOpenProfile();
              case 'report':
                onReport();
              case 'block':
                onBlock();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'mute',
              child: Row(
                children: [
                  Icon(isMuted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined),
                  const SizedBox(width: 12),
                  // Flexible, not a bare Text: several locales render these
                  // labels far longer than English ("Stummschaltung aufheben"),
                  // and an unconstrained Row in a popup menu overflows rather
                  // than wrapping.
                  Flexible(
                    child: Text(
                      isMuted
                          ? context.l10n.chatUnmuteNotifications
                          : context.l10n.chatMuteNotifications,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'profile',
              child: Row(
                children: [
                  const Icon(Icons.person_outline),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      context.l10n.chatViewProfile,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'report',
              child: Row(
                children: [
                  const Icon(Icons.flag_outlined),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      context.l10n.safetyReport,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'block',
              child: Row(
                children: [
                  Icon(Icons.block, color: AppTheme.errorColor),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      context.l10n.safetyBlock,
                      style: TextStyle(color: AppTheme.errorColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
