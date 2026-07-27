import 'package:flutter/material.dart';
import 'package:flame/theme/app_theme.dart';

/// A circular ring around a story avatar. Coral gradient when there are
/// unseen stories, grey when all seen. When [showPlus] is true (the user's own
/// tray item with no active story) it renders a dashed-free plain ring plus a
/// `+` badge is drawn by the caller.
class StoryGradientRing extends StatelessWidget {
  const StoryGradientRing({
    super.key,
    required this.child,
    required this.active,
    this.thickness = 3,
    this.dimmed = false,
  });

  final Widget child;
  final bool active;
  final double thickness;

  /// Grey, low-emphasis ring (e.g. the own item before any story exists).
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final ringColor = dimmed ? Colors.grey.shade400 : Colors.grey.shade300;
    return Container(
      padding: EdgeInsets.all(thickness),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: active
            ? const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        border: active ? null : Border.all(color: ringColor, width: thickness),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: child,
      ),
    );
  }
}
