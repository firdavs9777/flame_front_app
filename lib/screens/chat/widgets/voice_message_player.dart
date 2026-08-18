import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/providers/voice_playback_provider.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';

/// Inline player for a `voice`/`audio` chat message. Play/pause, a progress
/// bar driven by real playback position, and an elapsed/total time label.
/// Backed by the shared [voicePlaybackProvider] so only one plays at a time.
class VoiceMessagePlayer extends ConsumerWidget {
  const VoiceMessagePlayer({
    super.key,
    required this.url,
    required this.fallbackDuration,
    required this.isMe,
  });

  /// The audio source URL.
  final String url;

  /// Duration (seconds) shown before playback starts, from message media info.
  final int fallbackDuration;

  /// Whether this is the current user's message (drives coloring).
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(voicePlaybackProvider);
    final isActive = playback.activeUrl == url;
    final playing = isActive && playback.playing;
    final processing = isActive && playback.processing;

    // isMe bubbles are primary-coloured, so their foreground is onPrimary.
    final foreground = isMe ? context.onPrimary : AppTheme.primaryColor;
    final track = isMe
        ? context.onPrimary.withValues(alpha: 0.3)
        : context.divider;

    final totalSeconds = isActive && playback.duration.inSeconds > 0
        ? playback.duration.inSeconds
        : fallbackDuration;
    final elapsedSeconds = isActive ? playback.position.inSeconds : 0;
    final progress = (isActive && playback.duration.inMilliseconds > 0)
        ? (playback.position.inMilliseconds / playback.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final label = isActive && playing
        ? _formatDuration(elapsedSeconds)
        : _formatDuration(totalSeconds);

    return SizedBox(
      width: 200,
      child: Row(
        children: [
          GestureDetector(
            onTap: url.isEmpty
                ? null
                : () => ref.read(voicePlaybackProvider.notifier).toggle(url),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isMe
                    ? context.onPrimary.withValues(alpha: 0.2)
                    : AppTheme.primaryColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: processing
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(foreground),
                      ),
                    )
                  : Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      color: foreground,
                      size: 20,
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: track,
                    valueColor: AlwaysStoppedAnimation<Color>(foreground),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isMe
                    ? context.onPrimary.withValues(alpha: 0.7)
                    : context.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
