import 'package:flutter/material.dart';

import 'package:flame/core/navigation/app_routes.dart';
import 'package:flame/core/image/photo_variants.dart';
import 'package:flame/models/photo.dart';

/// Opens [photos] full screen, starting at [index].
///
/// One helper because three grids show the same photos and each of them used
/// to do something different when tapped: the edit-profile grid opened an
/// options sheet, the profile grid did nothing at all, and the avatar opened
/// the image picker. Two of those are not what tapping a photo means.
void openPhotoGallery(BuildContext context, List<Photo> photos, int index) {
  // The viewer shows one photo at a time, full-bleed, so it always wants the
  // full variant regardless of what the calling grid was drawing.
  final urls = photos
      .map((p) => photoUrlFor(p, PhotoSize.full))
      .where((u) => u.isNotEmpty)
      .toList();
  if (urls.isEmpty) return;

  Navigator.of(context).pushNamed(
    AppRoutes.mediaViewer,
    arguments: MediaViewerArgs.gallery(urls: urls, initialIndex: index),
  );
}
