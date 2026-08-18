import 'package:flutter/material.dart';

import 'package:flame/theme/app_theme.dart';

enum ChatSnackBarType { info, error }

/// One place chat reports a transient outcome.
///
/// Replaces `_ChatScreenState._showError`'s inline SnackBar, so a handler can
/// report without holding a State — and so error styling is decided once rather
/// than at each call site.
void showChatSnackBar(
  BuildContext context, {
  required String message,
  ChatSnackBarType type = ChatSnackBarType.info,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor:
          type == ChatSnackBarType.error ? AppTheme.errorColor : null,
    ),
  );
}
