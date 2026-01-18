import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flame/models/models.dart';
import 'package:flame/theme/app_theme.dart';

class ChatInput extends StatefulWidget {
  final TextEditingController controller;
  final bool isSending;
  final Message? replyingTo;
  final VoidCallback onSend;
  final VoidCallback? onCancelReply;
  final VoidCallback? onAttachmentTap;
  final VoidCallback? onStickerTap;
  final ValueChanged<String> onTextChanged;
  final void Function(File voiceFile, int durationSeconds)? onVoiceRecorded;

  const ChatInput({
    super.key,
    required this.controller,
    required this.isSending,
    this.replyingTo,
    required this.onSend,
    this.onCancelReply,
    this.onAttachmentTap,
    this.onStickerTap,
    required this.onTextChanged,
    this.onVoiceRecorded,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isCancelled = false;
  double _dragOffset = 0;
  int _recordingDuration = 0;
  String? _recordingPath;
  DateTime? _recordingStartTime;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const double _cancelThreshold = -80;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  bool get _hasText => widget.controller.text.trim().isNotEmpty;

  Future<void> _startRecording() async {
    if (widget.onVoiceRecorded == null) return;

    try {
      if (await _recorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        _recordingPath = '${directory.path}/voice_$timestamp.m4a';

        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 128000,
            sampleRate: 44100,
          ),
          path: _recordingPath!,
        );

        HapticFeedback.mediumImpact();

        setState(() {
          _isRecording = true;
          _isCancelled = false;
          _recordingDuration = 0;
          _dragOffset = 0;
          _recordingStartTime = DateTime.now();
        });

        _pulseController.repeat(reverse: true);
        _updateDuration();
      } else {
        _showPermissionDeniedSnackbar();
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  void _updateDuration() {
    if (!_isRecording) return;

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_isRecording && mounted && _recordingStartTime != null) {
        setState(() {
          _recordingDuration = DateTime.now().difference(_recordingStartTime!).inSeconds;
        });
        _updateDuration();
      }
    });
  }

  Future<void> _stopRecording({bool send = true}) async {
    if (!_isRecording) return;

    _pulseController.stop();
    _pulseController.reset();

    final wasRecording = _isRecording;
    final wasCancelled = _isCancelled;
    final duration = _recordingDuration;

    setState(() {
      _isRecording = false;
      _dragOffset = 0;
    });

    try {
      final path = await _recorder.stop();

      if (send && !wasCancelled && path != null && duration > 0 && wasRecording) {
        final file = File(path);
        if (await file.exists()) {
          widget.onVoiceRecorded?.call(file, duration);
        }
      } else {
        // Delete the recording if cancelled
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isRecording) return;

    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(-120.0, 0.0);
      final newCancelled = _dragOffset <= _cancelThreshold;

      if (newCancelled && !_isCancelled) {
        HapticFeedback.lightImpact();
      }
      _isCancelled = newCancelled;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_isCancelled) {
      _stopRecording(send: false);
    }
  }

  void _showPermissionDeniedSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Microphone permission is required to record voice messages'),
        backgroundColor: Colors.red,
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

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
            // Reply preview
            if (widget.replyingTo != null && !_isRecording) _buildReplyPreview(context),
            // Input row or recording UI
            _isRecording ? _buildRecordingRow() : _buildInputRow(context),
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
                  widget.replyingTo!.content,
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
            onPressed: widget.onCancelReply,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingRow() {
    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            // Recording indicator and duration
            Expanded(
              child: Transform.translate(
                offset: Offset(_dragOffset * 0.5, 0),
                child: Row(
                  children: [
                    // Recording dot
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.5 * _pulseAnimation.value),
                                blurRadius: 4 * _pulseAnimation.value,
                                spreadRadius: 1 * _pulseAnimation.value,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    // Duration
                    Text(
                      _formatDuration(_recordingDuration),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Slide to cancel hint
                    Icon(
                      Icons.chevron_left,
                      color: _isCancelled ? Colors.red : Colors.grey[400],
                      size: 20,
                    ),
                    Text(
                      _isCancelled ? 'Release to cancel' : 'Slide to cancel',
                      style: TextStyle(
                        fontSize: 13,
                        color: _isCancelled ? Colors.red : Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Mic button
            GestureDetector(
              onLongPressEnd: (_) => _stopRecording(send: !_isCancelled),
              child: Transform.translate(
                offset: Offset(_dragOffset, 0),
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isCancelled ? 0.8 : _pulseAnimation.value,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _isCancelled ? Colors.grey : AppTheme.primaryColor,
                          shape: BoxShape.circle,
                          boxShadow: _isCancelled
                              ? null
                              : [
                                  BoxShadow(
                                    color: AppTheme.primaryColor.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                        ),
                        child: Icon(
                          _isCancelled ? Icons.delete : Icons.mic,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attachment button
          IconButton(
            icon: Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
            onPressed: widget.onAttachmentTap,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              child: TextField(
                controller: widget.controller,
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
                  suffixIcon: IconButton(
                    icon: Icon(Icons.emoji_emotions_outlined, color: Colors.grey[500]),
                    onPressed: widget.onStickerTap,
                  ),
                ),
                textCapitalization: TextCapitalization.sentences,
                onChanged: widget.onTextChanged,
                onSubmitted: (_) => widget.onSend(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send or Mic button
          _hasText || widget.onVoiceRecorded == null
              ? _buildSendButton()
              : _buildMicButton(),
        ],
      ),
    );
  }

  Widget _buildSendButton() {
    return GestureDetector(
      onTap: widget.isSending ? null : widget.onSend,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.isSending ? Colors.grey : AppTheme.primaryColor,
          shape: BoxShape.circle,
        ),
        child: widget.isSending
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

  Widget _buildMicButton() {
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(send: !_isCancelled),
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.mic,
          color: Colors.grey[600],
          size: 22,
        ),
      ),
    );
  }
}
