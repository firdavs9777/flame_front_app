import 'package:flutter/material.dart';
import 'package:flame/theme/app_theme.dart';

/// Semantic colours, resolved from the active [ColorScheme].
///
/// Exists because 349 hardcoded `Colors.*` literals across the app override a
/// perfectly good light/dark theme. Reaching for `context.secondaryText` is
/// shorter than `Theme.of(context).colorScheme.onSurfaceVariant`, which is the
/// only reason the literals won in the first place.
///
/// Brand colours are NOT here: `AppTheme.primaryColor` is the brand in both
/// themes and does not vary with it.
extension AppTokens on BuildContext {
  ColorScheme get _scheme => Theme.of(this).colorScheme;

  /// Page and card backgrounds.
  Color get surface => _scheme.surface;

  /// Body text and icons on [surface].
  Color get onSurface => _scheme.onSurface;

  /// Captions, hints, timestamps — present but not the point.
  Color get secondaryText => _scheme.onSurfaceVariant;

  /// Input fills and inset panels.
  Color get fill => _scheme.surfaceContainerHighest;

  /// Hairlines between rows.
  ///
  /// `dividerTheme.color` first, because `AppTheme` sets it explicitly in both
  /// themes (`app_theme.dart:446` gray200 light, `:573` gray800 dark) while
  /// leaving `ThemeData.dividerColor` to be derived. Reading the derived value
  /// would quietly ignore the app's own choice.
  Color get divider =>
      Theme.of(this).dividerTheme.color ?? Theme.of(this).dividerColor;

  /// Text and icons sitting ON a primary-coloured surface — a filled button,
  /// a selected chip. Not the same as [surface]'s foreground.
  Color get onPrimary => _scheme.onPrimary;

  /// Foreground for content drawn over a dark scrim, a photo, or a coloured
  /// badge that isn't [AppTheme.primaryColor] — a carousel indicator dot, an
  /// icon on a semi-transparent overlay, text on a status badge.
  ///
  /// Deliberately NOT derived from [onPrimary]. It reads as the same white in
  /// both themes today only because `AppTheme` happens to set
  /// `onPrimary: AppColors.white` in both `ColorScheme.light()` and
  /// `ColorScheme.dark()` (`app_theme.dart:369,496`). Aliasing `onPrimary`
  /// here would make these sites silently go invisible the day someone
  /// rebrands `primaryColor` and its `onPrimary` foreground along with it —
  /// a change the lint test cannot see, because by then these are token
  /// references, not literals. This accessor exists so that rebrand can
  /// never touch overlay chrome that was never on a primary surface to begin
  /// with.
  Color get onOverlay => AppColors.white;

  /// The ground behind full-screen media, and the scrim over a video thumbnail.
  ///
  /// Deliberately the same in both themes: a photo viewer is black because black
  /// is what does not compete with the photo, not because the app is in dark
  /// mode. A token rather than a literal so the intent is recorded and the lint
  /// gate does not read it as an oversight.
  Color get viewerScrim => AppColors.black;
}
