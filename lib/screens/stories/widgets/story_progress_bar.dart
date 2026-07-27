import 'package:flutter/material.dart';

/// Segmented progress bar at the top of the story viewer — one segment per
/// story. Segments before [currentIndex] are full, the current fills by
/// [progress] (0..1), later segments are empty.
class StoryProgressBar extends StatelessWidget {
  const StoryProgressBar({
    super.key,
    required this.count,
    required this.currentIndex,
    required this.progress,
  });

  final int count;
  final int currentIndex;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (i) {
        double value;
        if (i < currentIndex) {
          value = 1;
        } else if (i == currentIndex) {
          value = progress.clamp(0.0, 1.0);
        } else {
          value = 0;
        }
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.35),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
        );
      }),
    );
  }
}
