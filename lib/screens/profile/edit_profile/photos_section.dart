import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/models/models.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';
import 'package:flame/widgets/smart_image.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/screens/profile/photo_gallery.dart';
import 'package:flame/core/image/photo_variants.dart';

class PhotosSection extends ConsumerStatefulWidget {
  final User user;

  const PhotosSection({required this.user});

  @override
  ConsumerState<PhotosSection> createState() => PhotosSectionState();
}

class PhotosSectionState extends ConsumerState<PhotosSection> {
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A drag gesture nobody can see is a feature nobody has. The second
        // sentence is the part that matters: reordering is how you change your
        // main photo, and that is not guessable from "drag to reorder".
        if (widget.user.photos.length > 1) ...[
          Text(
            context.l10n.profileReorderHint,
            style: TextStyle(fontSize: 12, color: context.secondaryText),
          ),
          const SizedBox(height: 12),
        ],
        _buildPhotosGrid(widget.user),
        if (_isUploading) ...[
          const SizedBox(height: 12),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }

  Widget _buildPhotosGrid(User user) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 6,
      itemBuilder: (context, index) {
        if (index < user.photos.length) {
          return _buildDraggableTile(user, index);
        }
        return _buildAddPhotoButton(index);
      },
    );
  }

  /// One photo, as both a drag source and a drop target.
  ///
  /// Long-press rather than plain drag: the grid scrolls with the page around
  /// it, and a tile that steals a vertical drag would make the section
  /// impossible to scroll past.
  ///
  /// ReorderableListView would have been less code, but it is a list — it lays
  /// out in one direction and cannot express a 3-across grid. The reorder is
  /// still a single move-one-to-a-position operation, which is exactly what the
  /// backend's full-permutation route wants.
  Widget _buildDraggableTile(User user, int index) {
    final photo = user.photos[index];
    final url = photoUrlFor(photo, PhotoSize.medium);
    final tile = _buildPhotoTile(url, index);

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => _movePhoto(details.data, index),
      builder: (context, candidate, rejected) {
        final hovered = candidate.isNotEmpty;
        return LongPressDraggable<int>(
          data: index,
          // The dragged copy is deliberately plain: the badge and the options
          // button belong to a position, and the whole point of the drag is
          // that the position is about to change.
          feedback: SizedBox(
            width: 96,
            height: 96,
            child: Opacity(
              opacity: 0.85,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SmartImage(imageSource: url, fit: BoxFit.cover),
              ),
            ),
          ),
          childWhenDragging: DecoratedBox(
            decoration: BoxDecoration(
              color: context.fill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const SizedBox.expand(),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: hovered
                  ? Border.all(color: AppTheme.primaryColor, width: 3)
                  : null,
            ),
            child: tile,
          ),
        );
      },
    );
  }

  Future<void> _movePhoto(int from, int to) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    final ok = await ref.read(currentUserProvider.notifier).movePhoto(from, to);
    if (!mounted) return;

    messenger.showSnackBar(SnackBar(
      content: Text(ok ? l10n.profilePhotosReordered : l10n.profileSaveFailed),
    ));
  }

  Widget _buildPhotoTile(String photoUrl, int index) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => openPhotoGallery(context, widget.user.photos, index),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SmartImage(
                imageSource: photoUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _showPhotoOptions(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.54),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.more_vert,
                color: context.onOverlay,
                size: 16,
              ),
            ),
          ),
        ),
        if (index == 0)
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                context.l10n.registerPhotoMainBadge,
                style: TextStyle(
                  color: context.onPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAddPhotoButton(int index) {
    return GestureDetector(
      onTap: () => _pickPhoto(index),
      child: Container(
        decoration: BoxDecoration(
          color: context.fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.divider,
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Icon(
          Icons.add_a_photo,
          size: 32,
          color: context.secondaryText,
        ),
      ),
    );
  }

  void _showPhotoOptions(int index) {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Only offered for a photo that is not already the main one — the
            // route rejects a no-op reorder, and offering an action that cannot
            // change anything is the shape this scope is removing.
            if (index > 0)
              ListTile(
                key: const Key('photo_set_main'),
                leading: const Icon(Icons.star_outline),
                title: Text(context.l10n.profileSetMainPhoto),
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await ref
                      .read(currentUserProvider.notifier)
                      .setMainPhotoAt(index);
                  if (!mounted) return;
                  if (!ok) {
                    messenger.showSnackBar(SnackBar(
                      content: Text(l10n.settingsSaveFailed),
                    ));
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(context.l10n.profileDeletePhoto, style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final ok = await ref
                    .read(currentUserProvider.notifier)
                    .deletePhotoAt(index);
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? context.l10n.profilePhotoDeleted
                        : context.l10n.profilePhotoDeleteFailed),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto(int index) async {
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(context.l10n.profileTakePhoto),
              onTap: () async {
                Navigator.pop(context);
                final photo = await picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 1024,
                  maxHeight: 1024,
                  imageQuality: 85,
                );
                if (photo != null) {
                  _uploadPhoto(File(photo.path));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(context.l10n.profileChooseFromGallery),
              onTap: () async {
                Navigator.pop(context);
                final photo = await picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1024,
                  maxHeight: 1024,
                  imageQuality: 85,
                );
                if (photo != null) {
                  _uploadPhoto(File(photo.path));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadPhoto(File photo) async {
    setState(() => _isUploading = true);

    final user = ref.read(currentUserProvider).valueOrNull;
    final isPrimary = user?.photos.isEmpty ?? true;

    final success = await ref.read(currentUserProvider.notifier).uploadPhoto(
      photo,
      isPrimary: isPrimary,
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? context.l10n.profilePhotoUploaded
            : context.l10n.profilePhotoUploadFailed),
      ),
    );
  }
}

/// Name, age and bio. Validates locally before calling [onSave] — an
/// invalid age or too-short name never reaches it — and keeps the user's
/// typed values on screen if the save fails, since [onSave] failing doesn't
/// touch [User] state at all.
