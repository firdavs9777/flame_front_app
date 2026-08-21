import 'package:flutter/material.dart';

import 'package:flame/theme/app_theme.dart';

enum SettingsSnackBarType { info, error }

/// One place Settings and Profile report a transient outcome, so error styling is
/// decided once. Mirrors chat_snackbar, following
/// bananatalk_app/lib/pages/settings/widgets/settings_snackbar.dart.
void showSettingsSnackBar(
  BuildContext context, {
  required String message,
  SettingsSnackBarType type = SettingsSnackBarType.info,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor:
          type == SettingsSnackBarType.error ? AppTheme.errorColor : null,
    ),
  );
}
