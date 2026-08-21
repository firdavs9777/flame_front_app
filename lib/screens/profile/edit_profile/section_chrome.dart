/// Chrome shared by all three edit-profile sections.
///
/// Here rather than in the composition root because the sections need it and
/// the root does too — a private helper in the root could not be reached once
/// the sections moved into their own files.
import 'package:flutter/material.dart';

import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

InputDecoration fieldDecoration(BuildContext context, String hint) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: context.fill,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}

/// A Save button in `AppTheme.primaryColor`, with [context.onPrimary] as its
/// foreground — text and spinner sit ON a primary-coloured surface.
///
/// [buttonKey] goes on the `ElevatedButton` itself rather than on this
/// wrapper: the wrapper's render object is the enclosing `Align`, which
/// spans the full row width, so a tap computed against its center would
/// land beside the (right-aligned) button rather than on it.
class SaveButton extends StatelessWidget {
  final Key buttonKey;
  final bool isSaving;
  final VoidCallback? onPressed;

  const SaveButton({
    required this.buttonKey,
    required this.isSaving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton(
        key: buttonKey,
        onPressed: isSaving ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: context.onPrimary,
        ),
        child: isSaving
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.onPrimary,
                ),
              )
            : const Text('Save'),
      ),
    );
  }
}

Widget fieldLabel(BuildContext context, String label) {
  return Text(
    label,
    style: TextStyle(fontWeight: FontWeight.w600, color: context.onSurface),
  );
}

/// Photos grid. Both actions it offers (upload, delete) save immediately
/// against the backend, so there is no separate Save button here — the
/// section is independent by construction.
///
/// It offers no reordering. An earlier "Set as main photo" item called
/// `CurrentUserNotifier.setMainPhotoAt` → `UserService.reorderPhotos` →
/// `PATCH /users/me/photos/reorder`, and **that route does not exist** — the
/// string `reorder` appears nowhere in the Flame backend. Every tap 404'd and
/// showed "Could not update main photo." Removed rather than left to fail.
///
/// `setMainPhotoAt` and `UserService.reorderPhotos` are deliberately kept, so
/// adding the route is all a future change needs. They have no caller outside
/// tests today.
