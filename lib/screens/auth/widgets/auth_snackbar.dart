import 'package:flutter/material.dart';

import 'package:flame/theme/app_theme.dart';

enum AuthSnackBarType { info, error, warning }

/// One place the auth surface reports a transient outcome.
///
/// Replaces fourteen inline SnackBars that each re-declared the same error
/// colour, floating behaviour and 12px radius. Mirrors chat_snackbar and
/// settings_snackbar, including their `context.mounted` guard — a handler can
/// report an outcome without first proving its widget is still alive.
void showAuthSnackBar(
  BuildContext context, {
  required String message,
  AuthSnackBarType type = AuthSnackBarType.info,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: switch (type) {
        AuthSnackBarType.error => AppTheme.errorColor,
        // AppColors.warning is 0xFFFF9800 — the orange step_bio_interests
        // already reaches for as a literal `Colors.orange`.
        AuthSnackBarType.warning => AppColors.warning,
        AuthSnackBarType.info => null,
      },
    ),
  );
}
