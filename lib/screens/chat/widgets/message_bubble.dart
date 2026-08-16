import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/screens/chat/media_viewer_screen.dart';
import 'package:flame/models/models.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/screens/chat/widgets/voice_message_player.dart';
import 'package:flame/providers/translation_provider.dart';
import 'package:flame/core/i18n/locale_provider.dart';
import 'package:flame/core/i18n/build_context_ext.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final VoidCallback? onLongPress;
  final void Function(String emoji)? onReact;
  final VoidCallback? onReply;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onLongPress,
    this.onReact,
    this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    // Handle deleted messages
    if (message.isDeleted) {
      return _buildDeletedMessage(context);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: onLongPress,
            child: Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe && message.reactions.isNotEmpty)
                  const SizedBox(width: 24), // Space for reactions
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.7,
                    ),
                    child: Column(
                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        // Reply preview if this is a reply
                        if (message.replyTo != null) _buildReplyPreview(context),
                        // Main message bubble
                        _buildBubble(context),
                      ],
                    ),
                  ),
                ),
                if (isMe && message.reactions.isNotEmpty)
                  const SizedBox(width: 24), // Space for reactions
              ],
            ),
          ),
          // Reactions display
          if (message.reactions.isNotEmpty) _buildReactions(context),
        ],
      ),
    );
  }

  Widget _buildDeletedMessage(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block, size: 16, color: Colors.grey[500]),
                const SizedBox(width: 8),
                Text(
                  'This message was deleted',
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(BuildContext context) {
    final reply = message.replyTo!;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe
            ? AppTheme.primaryColor.withValues(alpha: 0.3)
            : Colors.grey[300],
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white : AppTheme.primaryColor,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reply.senderName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isMe ? Colors.white : AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            reply.content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isMe ? Colors.white70 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? AppTheme.primaryColor : Colors.grey[200],
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMe ? 20 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildContent(context),
          const SizedBox(height: 4),
          _buildMeta(context),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (message.type) {
      case MessageType.image:
        return _buildImageContent(context);
      case MessageType.video:
        return _buildVideoContent();
      case MessageType.voice:
      case MessageType.audio:
        return _buildAudioContent();
      case MessageType.sticker:
        return _buildStickerContent();
      case MessageType.gif:
        return _buildGifContent();
      default:
        return _buildTextContent();
    }
  }

  Widget _buildTextContent() {
    final text = Text(
      message.content,
      style: TextStyle(
        color: isMe ? Colors.white : Colors.black87,
        fontSize: 15,
      ),
    );
    // Offer translation only for incoming, non-empty text messages.
    if (isMe || message.content.trim().isEmpty) return text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        text,
        _TranslateSection(message: message),
      ],
    );
  }

  Widget _buildImageContent(BuildContext context) {
    final imageUrl = message.imageUrl ?? message.content;
    return _MediaThumbnail(
      url: imageUrl,
      heroTag: 'msg-${message.id}',
      onTap: () => _openViewer(context, imageUrl),
    );
  }

  /// Opens the full-screen, zoomable view.
  ///
  /// The thumbnail deliberately does not try to be the whole experience: it is
  /// capped so it cannot dominate the thread, and this is how you actually look
  /// at the photo. Before this there was no tap target at all.
  void _openViewer(BuildContext context, String url) {
    if (url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(url: url, heroTag: 'msg-${message.id}'),
      ),
    );
  }

  Widget _buildVideoContent() {
    final thumbnailUrl = message.mediaInfo?.thumbnailUrl;
    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: thumbnailUrl != null
              ? Image.network(
                  thumbnailUrl,
                  width: 200,
                  height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 200,
                    height: 150,
                    color: Colors.grey[800],
                  ),
                )
              : Container(
                  width: 200,
                  height: 150,
                  color: Colors.grey[800],
                ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
        ),
        if (message.mediaInfo?.duration != null)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDuration(message.mediaInfo!.duration!),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAudioContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: VoiceMessagePlayer(
        url: message.audioUrl ?? message.content,
        fallbackDuration: message.mediaInfo?.duration ?? 0,
        isMe: isMe,
      ),
    );
  }

  Widget _buildStickerContent() {
    return Image.network(
      message.content,
      width: 120,
      height: 120,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const SizedBox(
        width: 120,
        height: 120,
        child: Icon(Icons.broken_image, size: 40),
      ),
    );
  }

  Widget _buildGifContent() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        message.content,
        width: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 200,
          height: 150,
          color: Colors.grey[300],
          child: const Icon(Icons.gif),
        ),
      ),
    );
  }

  Widget _buildMeta(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.isEdited) ...[
          Text(
            'edited',
            style: TextStyle(
              color: isMe ? Colors.white60 : Colors.grey[400],
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          message.timeText,
          style: TextStyle(
            color: isMe ? Colors.white70 : Colors.grey[500],
            fontSize: 11,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          _buildStatusIcon(),
        ],
      ],
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color;

    switch (message.status) {
      case MessageStatus.sending:
        icon = Icons.access_time;
        color = Colors.white54;
        break;
      case MessageStatus.sent:
        icon = Icons.done;
        color = Colors.white70;
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        color = Colors.white70;
        break;
      case MessageStatus.read:
        icon = Icons.done_all;
        color = Colors.blue.shade200;
        break;
      case MessageStatus.failed:
        icon = Icons.error_outline;
        color = Colors.red.shade200;
        break;
    }

    return Icon(icon, size: 14, color: color);
  }

  Widget _buildReactions(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        left: isMe ? 0 : 12,
        right: isMe ? 12 : 0,
      ),
      child: Wrap(
        spacing: 4,
        children: message.reactions.map((reaction) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              reaction.emoji,
              style: const TextStyle(fontSize: 14),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

/// Tap-to-translate affordance shown under incoming text messages. Reads the
/// per-message [translationProvider] cache and the app's target language.
class _TranslateSection extends ConsumerWidget {
  const _TranslateSection({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(translationProvider)[message.id];
    final target = ref.watch(localeProvider)?.languageCode ?? 'en';
    final status = entry?.status ?? TranslationStatus.idle;
    final showingTranslation =
        status == TranslationStatus.done && (entry?.visible ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        InkWell(
          onTap: status == TranslationStatus.loading
              ? null
              : () => ref.read(translationProvider.notifier).toggle(
                    messageId: message.id,
                    text: message.content,
                    targetLang: target,
                  ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.translate, size: 14, color: AppTheme.primaryColor),
              const SizedBox(width: 4),
              Text(
                showingTranslation
                    ? context.l10n.chatHideTranslation
                    : context.l10n.chatTranslate,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (status == TranslationStatus.loading)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 6),
                Text(
                  context.l10n.chatTranslating,
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        if (showingTranslation && entry?.text != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              entry!.text!,
              style: const TextStyle(fontSize: 15, color: Colors.black87),
            ),
          ),
        if (status == TranslationStatus.error)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              context.l10n.chatTranslationUnavailable,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: Colors.grey[500],
              ),
            ),
          ),
      ],
    );
  }
}

/// A chat media thumbnail: cached, decode-sized, and tappable.
///
/// Replaces a raw `Image.network(width: 200, fit: BoxFit.cover)`, which had
/// three problems at once. It refetched on every scroll because nothing cached
/// it; it decoded a full-resolution photo into a 200px slot, so a 12MP image
/// cost ~48MB of memory to show a thumbnail; and `cover` at a fixed width
/// cropped every photo that was not roughly the assumed shape.
///
/// `memCacheWidth` fixes the decode cost, and a max-width box with the image's
/// own aspect ratio preserved fixes the cropping — a portrait photo now reads
/// as a portrait photo.
class _MediaThumbnail extends StatelessWidget {
  final String url;
  final String? heroTag;
  final VoidCallback onTap;

  const _MediaThumbnail({
    required this.url,
    required this.onTap,
    this.heroTag,
  });

  // Roughly two thirds of a phone's width: big enough to see, small enough
  // that a photo does not push the surrounding conversation off screen.
  static const double _maxWidth = 240;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;

    final image = CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      // Decode at display size, not source size. The multiplier keeps it sharp
      // on high-DPI screens without decoding the original.
      memCacheWidth: (_maxWidth * dpr).round(),
      placeholder: (_, __) => Container(
        height: 160,
        color: Colors.grey[300],
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (_, __, ___) => Container(
        height: 160,
        color: Colors.grey[300],
        child: const Icon(Icons.broken_image_outlined),
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth, maxHeight: 320),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: heroTag == null ? image : Hero(tag: heroTag!, child: image),
        ),
      ),
    );
  }
}
