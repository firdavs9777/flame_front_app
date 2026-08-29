import 'package:flutter/material.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/services/location_service.dart';

/// Explains that signup cannot finish without a location, and offers the OS
/// settings page as the way out.
///
/// Shared by both signup paths: registration needs coordinates for
/// /auth/register, and social completion needs them for the same reason
/// registration does — the backend does not call a profile complete without
/// them. Two copies of this dialog would be two places to drift.
Future<void> showLocationRequiredDialog(
  BuildContext context, {
  required String error,
}) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.l10n.registerLocationRequiredTitle),
      content: Text('$error\n\n${context.l10n.registerLocationRequiredBody}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.registerCancel),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            await LocationService().openAppSettings();
          },
          child: Text(context.l10n.registerOpenSettings),
        ),
      ],
    ),
  );
}
