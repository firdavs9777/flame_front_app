import 'package:flutter/material.dart';

import 'package:flame/screens/chat/chat_attachments.dart';

/// The "share" sheet in the chat composer.
///
/// It used to offer six options — gallery, camera, video, voice, GIF and
/// sticker — but it hung off `ChatV2Screen`, which nothing navigated to, so
/// none of them were ever reachable. Now that it is wired into the live
/// composer it offers only what the backend actually accepts: GIF has no
/// endpoint at all, all five sticker endpoints 404 by design, and voice has a
/// backend and a player but no recorder UI yet. A button that cannot work is
/// worse than a missing one.
class AttachmentModal extends StatelessWidget {
  final ValueChanged<ChatAttachmentKind> onPick;

  const AttachmentModal({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('Share', style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _AttachmentOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  color: Colors.purple,
                  onTap: () => onPick(ChatAttachmentKind.gallery),
                ),
                _AttachmentOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  color: Colors.pink,
                  onTap: () => onPick(ChatAttachmentKind.camera),
                ),
                _AttachmentOption(
                  icon: Icons.videocam,
                  label: 'Video',
                  color: Colors.red,
                  onTap: () => onPick(ChatAttachmentKind.video),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // Opaque so the whole column is a tap target, not just the painted
      // pixels of the icon and label.
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}
