import 'package:flutter/material.dart';

import 'package:flame/core/languages/language_flags.dart';
import 'package:flame/theme/app_tokens.dart';

/// Small circular badge surfacing a language flag at a glance.
///
/// Mirrors BananaTalk's `LanguageFlagBadge` (lib/widgets/language_flag_badge.dart
/// there), which overlays the same corner of an avatar across their chat list,
/// community cards and moments feed. Flame's version takes a language CODE
/// (`languagesSpoken.first`, e.g. `'ko'`) rather than a display name, since
/// that is what [Language]/`User.languagesSpoken` actually store, and resolves
/// it through [LanguageFlags.getFlag] rather than a name lookup.
///
/// A text line (`LanguagesLine`) says the same thing in words; this says it
/// without requiring the words to be read. A reviewer skimming the deck for
/// three seconds sees the badge before they read anything.
///
/// Drop into a [Stack] alongside the photo:
/// ```dart
/// Stack(children: [
///   photo,
///   LanguageFlagBadge(code: user.languagesSpoken.firstOrNull),
/// ])
/// ```
class LanguageFlagBadge extends StatelessWidget {
  const LanguageFlagBadge({
    super.key,
    required this.code,
    this.size = 28,
    this.offset = 0,
    this.alignment = Alignment.bottomLeft,
  });

  /// The language code to render a flag for, or null/empty to render nothing.
  final String? code;

  /// Diameter of the badge circle. The flag glyph scales proportionally.
  final double size;

  /// Distance from the chosen corner of the enclosing [Stack].
  final double offset;

  /// Which corner of the enclosing [Stack] the badge sits in. Defaults to
  /// bottom-left, matching BananaTalk's avatar badge. The deck card's photo
  /// is full-bleed and already has the name/bio block anchored bottom-left,
  /// so that call site passes [Alignment.topLeft] instead.
  ///
  /// Only the four corners are meaningful here — anything else degrades to
  /// whichever corner its sign matches.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final c = code;
    if (c == null || c.isEmpty) return const SizedBox.shrink();
    final flag = LanguageFlags.getFlag(c);
    // getFlag never returns empty — it degrades to 🌐 — but an empty result
    // would still mean nothing worth drawing a badge around.
    if (flag.isEmpty) return const SizedBox.shrink();

    final surface = context.surface;
    return Positioned(
      top: alignment.y <= 0 ? offset : null,
      bottom: alignment.y > 0 ? offset : null,
      left: alignment.x <= 0 ? offset : null,
      right: alignment.x > 0 ? offset : null,
      child: Container(
        key: const Key('language_flag_badge'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: surface,
          shape: BoxShape.circle,
          border: Border.all(color: surface, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          flag,
          style: TextStyle(fontSize: size * 0.55, height: 1.0),
        ),
      ),
    );
  }
}
