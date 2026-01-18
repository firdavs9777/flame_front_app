import 'package:flutter/material.dart';
import 'package:flame/theme/app_theme.dart';

class ActionButtons extends StatelessWidget {
  final VoidCallback onDislike;
  final VoidCallback onSuperLike;
  final VoidCallback onLike;

  const ActionButtons({
    super.key,
    required this.onDislike,
    required this.onSuperLike,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Dislike button
        _ActionButton(
          icon: Icons.close,
          color: AppTheme.errorColor,
          size: 60,
          iconSize: 30,
          onTap: onDislike,
        ),
        const SizedBox(width: 20),
        // Super like button
        _ActionButton(
          icon: Icons.star,
          color: Colors.blue,
          size: 50,
          iconSize: 24,
          onTap: onSuperLike,
        ),
        const SizedBox(width: 20),
        // Like button
        _ActionButton(
          icon: Icons.favorite,
          color: AppTheme.successColor,
          size: 60,
          iconSize: 30,
          onTap: onLike,
        ),
      ],
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.iconSize,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward().then((_) {
      _controller.reverse();
      widget.onTap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTap: _handleTap,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(
            widget.icon,
            color: widget.color,
            size: widget.iconSize,
          ),
        ),
      ),
    );
  }
}
