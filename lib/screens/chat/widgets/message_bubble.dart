import 'package:flame/core/navigation/app_routes.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/screens/chat/widgets/voice_message_player.dart';
import 'package:flame/providers/translation_provider.dart';
import 'package:flame/screens/chat/state/auto_translate_scheduler.dart';
import 'package:flame/core/i18n/locale_provider.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/theme/app_tokens.dart';

/// The width every photo, gif and video thumbnail occupies in a thread.
///
/// Roughly two thirds of a phone's width: big enough to see, small enough that
/// a photo does not push the conversation off screen.
///
/// It is a fixed width rather than a maximum, and that is the point. As a
/// maximum it only ever capped: a small photo drew small, a tall one narrowed
/// to fit the height cap, and video and gif used a different number entirely —
/// so a thread of photos was a ragged column of different-sized rectangles.
const double kChatMediaWidth = 240;

/// How tall a medium may get before it is cropped instead.
///
/// Height still follows each image's own aspect ratio — a portrait photo reads
/// as a portrait photo — but a very tall one would otherwise fill the screen
/// and bury the messages around it. Tap opens the full, uncropped view.
const double kChatMediaMaxHeight = 320;

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final VoidCallback? onLongPress;
  final void Function(String emoji)? onReact;
  final VoidCallback? onReply;

  /// First of a run from one sender. Defaults true so a caller that does not
  /// group gets the pre-grouping layout unchanged.
  final bool isFirstInGroup;

  /// Last of a run. Only the last bubble carries the timestamp and delivery
  /// tick — repeating them on every message in a run is noise, since they are
  /// all within a few minutes of each other by definition.
  final bool isLastInGroup;

  /// Whether this thread has a KNOWN language mismatch — both people have
  /// declared spoken languages and share none — computed once for the whole
  /// conversation via `shouldDefaultTranslationOn` and passed down uniformly.
  ///
  /// Defaults false so every other call site (and every existing test) keeps
  /// today's opt-in behaviour. Only an incoming text bubble acts on it — it
  /// makes translation begin automatically instead of waiting for a tap.
  final bool translateDefaultOn;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onLongPress,
    this.onReact,
    this.onReply,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.translateDefaultOn = false,
  });

  @override
  Widget build(BuildContext context) {
    // Handle deleted messages
    if (message.isDeleted) {
      return _buildDeletedMessage(context);
    }

    return Padding(
      // Tight inside a run, roomy between runs: the gap is what makes a group
      // read as one utterance rather than several.
      padding: EdgeInsets.only(bottom: isLastInGroup ? 12 : 2),
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
              color: context.fill,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block, size: 16, color: context.secondaryText),
                const SizedBox(width: 8),
                Text(
                  context.l10n.chatMessageDeleted,
                  style: TextStyle(
                    color: context.secondaryText,
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
            : context.divider,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: isMe ? context.onPrimary : AppTheme.primaryColor,
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
              color: isMe ? context.onPrimary : AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            reply.content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isMe
                ? context.onPrimary.withValues(alpha: 0.7)
                : context.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  /// Content that is its own shape and gets no pill.
  ///
  /// A sticker was always here: a big emoji inside a coloured bubble reads as a
  /// typo, which is why every chat app renders them bare. Media joins it for the
  /// same reason — the pill's 16/10 padding plus its fill drew a visible frame
  /// around every photo, brand-coloured on the way out and grey on the way in.
  /// A photograph does not need a coloured mount.
  ///
  /// Voice and audio deliberately stay on the pill: a player is controls, and
  /// controls need a surface to sit on.
  bool get _isBare =>
      message.type == MessageType.sticker ||
      message.type == MessageType.image ||
      message.type == MessageType.video ||
      message.type == MessageType.gif;

  /// The bubble's shape — square-ish on the tail corner that points at its
  /// sender. Stated once so bare media can take the same shape: with no pill
  /// behind it, the picture *is* the bubble, and a flat 12px rounding made it
  /// read as a floating thumbnail rather than a message.
  BorderRadius _bubbleRadius() => BorderRadius.only(
        topLeft: const Radius.circular(20),
        topRight: const Radius.circular(20),
        bottomLeft: Radius.circular(isMe ? 20 : 4),
        bottomRight: Radius.circular(isMe ? 4 : 20),
      );

  Widget _buildBubble(BuildContext context) {
    final bare = _isBare;

    return Container(
      padding: bare
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: bare
            ? Colors.transparent
            : (isMe ? AppTheme.primaryColor : context.fill),
        borderRadius: _bubbleRadius(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildContent(context),
          // No pill means no padding, so the meta needs its own breathing room
          // rather than borrowing the bubble's.
          SizedBox(height: bare ? 2 : 4),
          if (isLastInGroup) _buildMeta(context),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (message.type) {
      case MessageType.image:
        return _buildImageContent(context);
      case MessageType.video:
        return _buildVideoContent(context);
      case MessageType.voice:
      case MessageType.audio:
        return _buildAudioContent();
      case MessageType.sticker:
        return _buildStickerContent();
      case MessageType.gif:
        return _buildGifContent(context);
      default:
        return _buildTextContent(context);
    }
  }

  Widget _buildTextContent(BuildContext context) {
    final text = Text(
      message.content,
      style: TextStyle(
        color: isMe ? context.onPrimary : context.onSurface,
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
        _TranslateSection(message: message, defaultOn: translateDefaultOn),
      ],
    );
  }

  Widget _buildImageContent(BuildContext context) {
    final imageUrl = message.imageUrl ?? message.content;
    return _MediaThumbnail(
      url: imageUrl,
      heroTag: 'msg-${message.id}',
      borderRadius: _bubbleRadius(),
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
    Navigator.of(context).pushNamed(
      AppRoutes.mediaViewer,
      arguments: MediaViewerArgs(url: url, heroTag: 'msg-${message.id}'),
    );
  }

  Widget _buildVideoContent(BuildContext context) {
    final thumbnailUrl = message.mediaInfo?.thumbnailUrl;
    // 16:9 within the shared media width, so a video sits in the same column as
    // the photos around it instead of at its own private size.
    const height = kChatMediaWidth * 9 / 16;
    return Stack(
      key: const Key('chat-media'),
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: _bubbleRadius(),
          child: thumbnailUrl != null
              ? Image.network(
                  thumbnailUrl,
                  width: kChatMediaWidth,
                  height: height,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: kChatMediaWidth,
                    height: height,
                    color: context.fill,
                  ),
                )
              : Container(
                  width: kChatMediaWidth,
                  height: height,
                  color: context.fill,
                ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.viewerScrim.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.play_arrow, color: context.onOverlay, size: 32),
        ),
        if (message.mediaInfo?.duration != null)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: context.viewerScrim.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDuration(message.mediaInfo!.duration!),
                style: TextStyle(color: context.onOverlay, fontSize: 12),
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

  /// A sticker is an emoji carried in the message text.
  ///
  /// This used to be `Image.network(message.content)` — the pack-and-artwork
  /// model Flame's inherited sticker code assumed, which no backend has ever
  /// supported. An emoji is not a URL, so every sticker rendered as a
  /// broken-image icon.
  Widget _buildStickerContent() {
    return Text(message.content, style: const TextStyle(fontSize: 48));
  }

  Widget _buildGifContent(BuildContext context) {
    return SizedBox(
      key: const Key('chat-media'),
      width: kChatMediaWidth,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: kChatMediaMaxHeight),
        child: ClipRRect(
          borderRadius: _bubbleRadius(),
          child: Image.network(
            message.content,
            width: kChatMediaWidth,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: kChatMediaWidth,
              height: kChatMediaWidth * 3 / 4,
              color: context.divider,
              child: const Icon(Icons.gif),
            ),
          ),
        ),
      ),
    );
  }

  /// The colour for the timestamp, the "edited" marker and the delivery tick.
  ///
  /// `onPrimary` is only correct when the meta sits ON the brand-coloured pill.
  /// A bare bubble has no pill, so the meta sits on the page — and `onPrimary`
  /// is white in both themes, which is invisible there in light mode. That was
  /// already true of stickers before media joined them.
  Color _metaColour(BuildContext context, {double onPillAlpha = 0.7}) {
    if (_isBare || !isMe) return context.secondaryText;
    return context.onPrimary.withValues(alpha: onPillAlpha);
  }

  Widget _buildMeta(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.isEdited) ...[
          Text(
            'edited',
            style: TextStyle(
              color: _metaColour(context, onPillAlpha: 0.6),
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          message.timeText,
          style: TextStyle(
            color: _metaColour(context),
            fontSize: 11,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          _buildStatusIcon(context),
        ],
      ],
    );
  }

  Widget _buildStatusIcon(BuildContext context) {
    IconData icon;
    Color color;

    switch (message.status) {
      case MessageStatus.sending:
        icon = Icons.access_time;
        color = _metaColour(context, onPillAlpha: 0.54);
        break;
      case MessageStatus.sent:
        icon = Icons.done;
        color = _metaColour(context);
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all;
        color = _metaColour(context);
        break;
      case MessageStatus.read:
        icon = Icons.done_all;
        color = AppColors.readReceipt;
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
              color: context.fill,
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
///
/// Stateful only so [defaultOn] can kick off a translation once, in
/// `initState`, rather than on every rebuild — `toggle` flips visibility on a
/// second call, so calling it from `build` would fight the user's own tap.
class _TranslateSection extends ConsumerStatefulWidget {
  const _TranslateSection({required this.message, this.defaultOn = false});

  final Message message;

  /// True when this thread has a known language mismatch. Translation begins
  /// automatically instead of waiting for a tap — but only once, and only if
  /// nothing has touched this message's cache entry yet, so a user who taps
  /// "Hide translation" stays hidden even if this widget rebuilds.
  final bool defaultOn;

  @override
  ConsumerState<_TranslateSection> createState() => _TranslateSectionState();
}

class _TranslateSectionState extends ConsumerState<_TranslateSection> {
  AutoTranslateScheduler? _scheduler;

  @override
  void initState() {
    super.initState();
    if (!widget.defaultOn) return;

    // Delayed, and capped, because `/translate` is a metered, rate-limited
    // endpoint. Opening a thread jumps the scroll position to the bottom,
    // which forces a non-reversed ListView to build (and promptly unmount)
    // every bubble from the top just to compute total extent — without the
    // delay, every one of those transient bubbles would fire a request. The
    // delay lets `cancel()` in dispose() catch them first; the gate caps
    // whatever is left mounted once the burst settles. See
    // AutoTranslateScheduler and AutoTranslateGate.
    _scheduler = AutoTranslateScheduler()
      ..start(
        gate: ref.read(autoTranslateGateProvider),
        fire: () async {
          if (!mounted) return;
          final entry = ref.read(translationProvider)[widget.message.id];
          // idle only: a cached entry — done, loading, or error — means
          // either this ran once already or the user has already acted on
          // it (including while this attempt sat queued behind the cap).
          if (entry != null) return;
          final target = ref.read(localeProvider)?.languageCode ?? 'en';
          await ref.read(translationProvider.notifier).toggle(
                messageId: widget.message.id,
                text: widget.message.content,
                targetLang: target,
              );
        },
      );
  }

  @override
  void dispose() {
    // Unconditional: a bubble that mounted only transiently during the
    // opening `jumpTo` layout pass disposes well inside the delay, so this
    // is what keeps it from ever reaching the gate, let alone the network.
    _scheduler?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
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
                    color: context.secondaryText,
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
              style: TextStyle(fontSize: 15, color: context.onSurface),
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
                color: context.secondaryText,
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
/// `memCacheWidth` fixes the decode cost, and preserving the image's own aspect
/// ratio fixes the cropping — a portrait photo reads as a portrait photo.
///
/// The width is fixed at [kChatMediaWidth] rather than merely capped there. A
/// cap left every photo a different width, which read as a bug; the height is
/// what varies with the picture's shape, bounded by [kChatMediaMaxHeight].
class _MediaThumbnail extends StatelessWidget {
  final String url;
  final String? heroTag;
  final VoidCallback onTap;

  /// The bubble's own shape, since a bare photo is the bubble.
  final BorderRadius borderRadius;

  const _MediaThumbnail({
    required this.url,
    required this.onTap,
    required this.borderRadius,
    this.heroTag,
  });

  /// What a medium occupies before its own dimensions are known — the
  /// placeholder, the error state, and a 4:3 default. Without this the
  /// placeholder had no width, so every bubble resized the instant its photo
  /// arrived and the whole thread reflowed while scrolling.
  static const double _pendingHeight = kChatMediaWidth * 3 / 4;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;

    Widget pending(Widget child) => Container(
          width: kChatMediaWidth,
          height: _pendingHeight,
          color: context.divider,
          child: Center(child: child),
        );

    final image = CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      // Decode at display size, not source size. The multiplier keeps it sharp
      // on high-DPI screens without decoding the original.
      memCacheWidth: (kChatMediaWidth * dpr).round(),
      placeholder: (_, __) =>
          pending(const CircularProgressIndicator(strokeWidth: 2)),
      errorWidget: (_, __, ___) =>
          pending(const Icon(Icons.broken_image_outlined)),
    );

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        key: const Key('chat-media'),
        width: kChatMediaWidth,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: kChatMediaMaxHeight),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: heroTag == null ? image : Hero(tag: heroTag!, child: image),
          ),
        ),
      ),
    );
  }
}
