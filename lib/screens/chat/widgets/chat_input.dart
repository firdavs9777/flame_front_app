import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flame/screens/chat/voice_recording.dart';
import 'package:flame/models/models.dart';
import 'package:flame/theme/app_theme.dart';

/// The chat composer: text, replies, and photo/video attachments.
///
/// This was text-only for as long as the backend had no media endpoints. It
/// now does, and the message bubble already renders what comes back, so the
/// attach affordance is real — but it appears only when [onAttach] is
/// supplied, so a caller that cannot handle attachments never shows a button
/// that does nothing. The mic follows the same rule: it appears only when
/// [onStartRecording] is supplied, and takes the send button's slot while the
/// field is empty. Stickers remain absent — those endpoints 404 by design.
class ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final bool isSending;
  final Message? replyingTo;
  final VoidCallback onSend;
  final VoidCallback? onCancelReply;
  final ValueChanged<String>? onChanged;

  /// Opens the attachment sheet. Null hides the affordance entirely.
  final VoidCallback? onAttach;

  /// Begins a voice recording. Null hides the mic, so the send button simply
  /// stays put — a composer that cannot record must not show a mic.
  final VoidCallback? onStartRecording;

  /// True while a recording is in progress: the text field is replaced by a
  /// timer with discard and send.
  final bool isRecording;
  final Duration recordingElapsed;
  final VoidCallback? onCancelRecording;
  final VoidCallback? onSendRecording;

  const ChatInput({
    super.key,
    required this.controller,
    required this.isSending,
    this.replyingTo,
    required this.onSend,
    this.onCancelReply,
    this.onChanged,
    this.onAttach,
    this.onStartRecording,
    this.isRecording = false,
    this.recordingElapsed = Duration.zero,
    this.onCancelRecording,
    this.onSendRecording,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (replyingTo != null && !isRecording) _buildReplyPreview(context),
            if (isRecording) _buildRecordingRow(context) else _buildInputRow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyPreview(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          left: BorderSide(color: AppTheme.primaryColor, width: 4),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  replyingTo!.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: onCancelReply,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (onAttach != null) _buildAttachButton(),
          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              child: TextField(
                controller: controller,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                textCapitalization: TextCapitalization.sentences,
                onChanged: onChanged,
                onSubmitted: (_) => onSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // One slot, not two buttons competing for the corner: a mic while the
          // field is empty, a send button the moment there is something to send.
          // Same shape as BananaTalk's chat_input_bar.dart.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              if (!hasText && onStartRecording != null) return _buildMicButton();
              return _buildSendButton();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMicButton() {
    return GestureDetector(
      onTap: isSending ? null : onStartRecording,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSending ? Colors.grey : AppTheme.primaryColor,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.mic, color: Colors.white, size: 20),
      ),
    );
  }

  /// What the composer becomes while recording: no text field, because typing
  /// mid-recording is not something the user can do, and both exits visible.
  Widget _buildRecordingRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: Theme.of(context).colorScheme.error,
            onPressed: onCancelRecording,
            tooltip: 'Discard recording',
          ),
          const SizedBox(width: 4),
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatRecordingTime(recordingElapsed),
            style: const TextStyle(
              fontSize: 16,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onSendRecording,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  /// Disabled while a send is in flight, for the same reason as the send
  /// button: starting a second upload on top of one already running is a
  /// mistake, not an intent.
  Widget _buildAttachButton() {
    return IconButton(
      onPressed: isSending ? null : onAttach,
      icon: const Icon(Icons.add_circle_outline),
      color: AppTheme.primaryColor,
      tooltip: 'Attach a photo or video',
    );
  }

  Widget _buildSendButton() {
    return GestureDetector(
      onTap: isSending ? null : onSend,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSending ? Colors.grey : AppTheme.primaryColor,
          shape: BoxShape.circle,
        ),
        child: isSending
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.send,
                color: Colors.white,
                size: 20,
              ),
      ),
    );
  }
}
