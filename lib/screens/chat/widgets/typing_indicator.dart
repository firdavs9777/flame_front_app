import 'package:flutter/material.dart';
import 'package:flame/widgets/smart_image.dart';

class TypingIndicator extends StatelessWidget {
  final String userPhotoUrl;

  const TypingIndicator({
    super.key,
    required this.userPhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundImage: userPhotoUrl.toImageProvider(),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TypingDot(delay: 0),
                SizedBox(width: 4),
                TypingDot(delay: 150),
                SizedBox(width: 4),
                TypingDot(delay: 300),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TypingDot extends StatefulWidget {
  final int delay;

  const TypingDot({super.key, required this.delay});

  @override
  State<TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<TypingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.grey[500]!.withValues(alpha: 0.5 + _animation.value * 0.5),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

class RecordingVoiceIndicator extends StatelessWidget {
  final String userPhotoUrl;

  const RecordingVoiceIndicator({
    super.key,
    required this.userPhotoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundImage: userPhotoUrl.toImageProvider(),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mic, size: 16, color: Colors.red[400]),
                const SizedBox(width: 4),
                Text(
                  'Recording voice...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
