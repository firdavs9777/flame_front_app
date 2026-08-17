import 'package:flutter/material.dart';

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
}
