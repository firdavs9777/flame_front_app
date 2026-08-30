import 'package:flutter/material.dart';

import 'package:flame/core/navigation/app_routes.dart';

/// Opens [photos] full screen, starting at [index].
///
/// One helper because three grids show the same photos and each of them used
/// to do something different when tapped: the edit-profile grid opened an
/// options sheet, the profile grid did nothing at all, and the avatar opened
/// the image picker. Two of those are not what tapping a photo means.
void openPhotoGallery(BuildContext context, List<String> photos, int index) {
  final urls = photos.where((p) => p.isNotEmpty).toList();
  if (urls.isEmpty) return;

  Navigator.of(context).pushNamed(
    AppRoutes.mediaViewer,
    arguments: MediaViewerArgs.gallery(urls: urls, initialIndex: index),
  );
}
