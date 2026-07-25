# Voice Message Playback — Design

**Date:** 2026-07-25
**Status:** Approved for implementation
**Scope:** Wire real audio playback into chat voice/audio messages. Recording and sending already exist; only playback is missing.

## Background

Flame's chat already records voice notes (`chat_input.dart` via the `record` package), sends them (`chat_screen` → `conversationsProvider.sendVoiceMessage` → `ChatService.sendVoiceMessage`), and models them (`Message.audioUrl`, `MessageType.voice`/`audio`). But `message_bubble._buildAudioContent()` is a static placeholder — a mic icon, a grey "waveform placeholder" bar, and a duration label — with no play control and no player. There is no audio-playback package in the project (`record` records only).

## Goal

Play back `voice` and `audio` messages inline in the chat bubble: a play/pause control, a real progress bar driven by playback position, and a time label. Only one message plays at a time.

### Non-goals

- Real waveform rendering (a progress bar stands in for it).
- Background/lock-screen audio, playback speed, scrubbing gestures beyond tap-to-seek.
- Changes to recording or sending (already work).

## Design

**Dependency:** add `just_audio` (standard, maintained playback lib).

**`voicePlaybackProvider`** (`lib/providers/voice_playback_provider.dart`) — a `StateNotifierProvider` owning a single `AudioPlayer`:
- State: `activeUrl` (String?), `processing`/`playing` (bool), `position` (Duration), `duration` (Duration).
- The `AudioPlayer` is created lazily on first `toggle()` so merely rendering a bubble never touches the native plugin (keeps widget tests plugin-free).
- `toggle(url)`: if `url` is active and playing → pause; if active and paused → resume; otherwise set the new URL and play (implicitly stops the previous one — single player = one-at-a-time).
- Subscribes to the player's `positionStream`, `durationStream`, and `playerStateStream` to update state; resets to idle on completion.
- Disposes the player in `dispose()`.

**`VoiceMessagePlayer`** (`lib/screens/chat/widgets/voice_message_player.dart`) — a `ConsumerWidget`:
- Inputs: `url`, `fallbackDuration` (from `mediaInfo.duration`, shown before playback), `isMe` (bubble-side coloring).
- Renders: circular play/pause button (spinner while `processing`), a `LinearProgressIndicator` bound to `position/duration` (falls back to 0 progress when idle), and a time label showing elapsed while active else total duration.
- Only reflects position for the bubble whose `url == activeUrl`; other bubbles show idle.

**Wiring:** `message_bubble._buildAudioContent()` returns `VoiceMessagePlayer(url: message.audioUrl ?? message.content, fallbackDuration: message.mediaInfo?.duration ?? 0, isMe: isMe)` for `voice` and `audio` types. Bubble stays otherwise unchanged.

## Testing

- Widget test: `VoiceMessagePlayer` renders a play icon and the formatted fallback duration without instantiating `AudioPlayer` (idle state, no plugin call).
- `flutter analyze` clean; full suite green.

## Risks

- **Plugin in tests** → lazy player creation keeps the idle render plugin-free; we don't unit-test actual playback (needs method-channel mocks / integration test).
- **Remote URL auth** → voice URLs are already returned by the backend for received messages; playback uses the same URL the bubble is given. If a URL needs auth headers, that's a follow-up (out of scope).
