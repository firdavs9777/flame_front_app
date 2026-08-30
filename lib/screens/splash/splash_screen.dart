import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flame/core/i18n/build_context_ext.dart';

/// Holds the brand screen until the app knows who the user is.
///
/// It used to hold for a flat 2500ms and then show [child] whatever state the
/// session restore was in. That produced both halves of the same complaint: a
/// returning user whose session restored in 200ms still waited two and a half
/// seconds, and a user whose restore took longer than that got dropped on the
/// welcome screen for a moment before being yanked to the main tabs — because
/// `AuthStatus.initial` is neither authenticated nor profile-incomplete, so
/// the router's ternary fell through to "signed out".
class SplashScreen extends StatefulWidget {
  final Widget child;

  /// Whether the session has been resolved — signed in or not, either is an
  /// answer. False means the app does not yet know, and showing [child] would
  /// be showing a guess.
  final bool ready;

  const SplashScreen({super.key, required this.child, this.ready = true});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// Long enough that the brand does not flash past on a warm start, short
  /// enough that nobody notices waiting.
  static const _minimumVisible = Duration(milliseconds: 700);

  /// A restore that never answers must not strand the user on a logo. The
  /// request behind it has its own 30s timeout, which is far too long to sit
  /// looking at nothing; past this the app shows its best guess instead.
  static const _ceiling = Duration(seconds: 5);

  bool _minimumElapsed = false;
  bool _gaveUpWaiting = false;

  // Held so they can be cancelled: a pending callback that fires after dispose
  // is a leak, and setState on a dead State throws.
  Timer? _minimumTimer;
  Timer? _ceilingTimer;

  @override
  void initState() {
    super.initState();
    FlutterNativeSplash.remove();
    _minimumTimer = Timer(_minimumVisible, () {
      if (mounted) setState(() => _minimumElapsed = true);
    });
    _ceilingTimer = Timer(_ceiling, () {
      if (mounted) setState(() => _gaveUpWaiting = true);
    });
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    _ceilingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settled = widget.ready || _gaveUpWaiting;
    if (!_minimumElapsed || !settled) {
      return _buildSplashContent();
    }
    return widget.child;
  }

  Widget _buildSplashContent() {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            // Sampled from the logo, so the native splash (a flat #CF461E with
            // the same droplet) hands over to this without a colour jump. The
            // middle stop used to be #E75A7C, the previous pink brand.
            colors: [Color(0xFFF4A523), Color(0xFFCF461E), Color(0xFF5C0F14)],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Was a stock Material flame glyph, which is not the logo.
              Image.asset(
                    'assets/images/logo_mark.png',
                    width: 96,
                    height: 96,
                  )
                  .animate()
                  .fadeIn(duration: 600.ms)
                  .scale(
                    begin: const Offset(0.5, 0.5),
                    end: const Offset(1, 1),
                    duration: 600.ms,
                    curve: Curves.elasticOut,
                  ),
              const SizedBox(height: 24),
              ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Colors.white, Color(0xFFFFE0E0)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ).createShader(bounds),
                    child: const Text(
                      'Flame',
                      style: TextStyle(
                        fontSize: 56,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 4,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            offset: Offset(0, 4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 300.ms, duration: 600.ms)
                  .slideY(
                    begin: 0.3,
                    end: 0,
                    delay: 300.ms,
                    duration: 600.ms,
                    curve: Curves.easeOutCubic,
                  ),
              const SizedBox(height: 12),
              Text(
                    context.l10n.welcomeHeadline,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.9),
                      letterSpacing: 2,
                    ),
                  )
                  .animate()
                  .fadeIn(delay: 600.ms, duration: 600.ms)
                  .slideY(
                    begin: 0.3,
                    end: 0,
                    delay: 600.ms,
                    duration: 600.ms,
                    curve: Curves.easeOutCubic,
                  ),
              const SizedBox(height: 60),
              // Loading indicator
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ).animate().fadeIn(delay: 900.ms, duration: 400.ms),
            ],
          ),
        ),
      ),
    );
  }
}
