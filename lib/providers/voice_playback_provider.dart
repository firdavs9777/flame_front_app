import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Snapshot of the single shared voice-message player.
class VoicePlaybackState {
  /// The URL currently loaded into the player, or null when idle.
  final String? activeUrl;
  final bool playing;

  /// True while the player is loading/buffering a source.
  final bool processing;
  final Duration position;
  final Duration duration;

  const VoicePlaybackState({
    this.activeUrl,
    this.playing = false,
    this.processing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
  });

  VoicePlaybackState copyWith({
    String? activeUrl,
    bool? playing,
    bool? processing,
    Duration? position,
    Duration? duration,
  }) {
    return VoicePlaybackState(
      activeUrl: activeUrl ?? this.activeUrl,
      playing: playing ?? this.playing,
      processing: processing ?? this.processing,
      position: position ?? this.position,
      duration: duration ?? this.duration,
    );
  }

  VoicePlaybackState idle() => const VoicePlaybackState();
}

/// Owns a single [AudioPlayer] so at most one voice message plays at a time.
///
/// The player is created lazily on first [toggle] — merely constructing the
/// notifier (e.g. when a chat renders) never touches the native plugin, which
/// keeps widget tests plugin-free.
class VoicePlaybackNotifier extends StateNotifier<VoicePlaybackState> {
  VoicePlaybackNotifier() : super(const VoicePlaybackState());

  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;

    final player = AudioPlayer();
    _player = player;

    _positionSub = player.positionStream.listen((pos) {
      if (!mounted) return;
      state = state.copyWith(position: pos);
    });
    _durationSub = player.durationStream.listen((dur) {
      if (!mounted) return;
      state = state.copyWith(duration: dur ?? Duration.zero);
    });
    _stateSub = player.playerStateStream.listen((ps) {
      if (!mounted) return;
      final processing = ps.processingState == ProcessingState.loading ||
          ps.processingState == ProcessingState.buffering;
      if (ps.processingState == ProcessingState.completed) {
        // Reset to the start and stop when the clip finishes.
        player.seek(Duration.zero);
        player.pause();
        state = state.copyWith(
          playing: false,
          processing: false,
          position: Duration.zero,
        );
        return;
      }
      state = state.copyWith(playing: ps.playing, processing: processing);
    });

    return player;
  }

  /// Play/pause [url]. If it's already the active clip, toggles play/pause;
  /// otherwise loads and plays it (replacing whatever was playing before).
  Future<void> toggle(String url) async {
    if (url.isEmpty) return;
    final player = _ensurePlayer();

    if (state.activeUrl == url) {
      if (player.playing) {
        await player.pause();
      } else {
        await player.play();
      }
      return;
    }

    state = state.copyWith(
      activeUrl: url,
      processing: true,
      playing: false,
      position: Duration.zero,
      duration: Duration.zero,
    );
    try {
      await player.setUrl(url);
      await player.play();
    } catch (_) {
      // Bad/unreachable URL — fall back to idle rather than a stuck spinner.
      state = const VoicePlaybackState();
    }
  }

  Future<void> seek(Duration position) async {
    if (_player == null) return;
    await _player!.seek(position);
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _player?.dispose();
    super.dispose();
  }
}

final voicePlaybackProvider =
    StateNotifierProvider<VoicePlaybackNotifier, VoicePlaybackState>(
  (ref) => VoicePlaybackNotifier(),
);
