import 'package:flutter/material.dart';

/// The warm gradient every unauthenticated screen sits on.
///
/// Declared once because four screens each carried their own copy of these two
/// stops, and a fifth would have made five.
const LinearGradient kAuthGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
);

/// Gradient background, SafeArea, and the translucent rounded back button
/// shared by login, forgot-password and both registration flows.
///
/// [onBack] null means no back affordance at all — the button is not merely
/// disabled, it is absent, so nothing occupies the corner.
///
/// [scrollable] wraps the child in a [SingleChildScrollView]. The wizard passes
/// false: it owns an [Expanded] PageView, which cannot live inside an
/// unbounded scroll view.
class AuthGradientScaffold extends StatelessWidget {
  const AuthGradientScaffold({
    super.key,
    required this.child,
    this.onBack,
    this.scrollable = true,
  });

  final Widget child;
  final VoidCallback? onBack;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onBack != null) ...[
          const SizedBox(height: 16),
          _BackButton(onPressed: onBack!),
        ],
        if (scrollable) child else Expanded(child: child),
      ],
    );

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: kAuthGradient),
        child: SafeArea(
          child: scrollable
              ? SingleChildScrollView(child: content)
              : content,
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.arrow_back_ios_new_rounded,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}
