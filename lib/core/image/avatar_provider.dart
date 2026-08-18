import 'package:flutter/widgets.dart';

import 'package:flame/widgets/smart_image.dart';

/// An [ImageProvider] for an avatar, decoded at the size it will actually be
/// drawn.
///
/// `String.toImageProvider()` decodes at full resolution, so a 2000px profile
/// photo was being decoded and uploaded to the GPU to fill a 40px circle — at
/// every avatar site in chat, because only `message_bubble.dart` ever passed
/// `memCacheWidth`.
///
/// [diameter] is required rather than optional on purpose: it makes the
/// un-downscaled version unavailable instead of merely discouraged. Callers pass
/// the same logical size they give the `CircleAvatar`.
ImageProvider? avatarProvider(
  String? source, {
  required double diameter,
  required double devicePixelRatio,
}) {
  if (source == null || source.isEmpty) return null;
  return ResizeImage(
    source.toImageProvider(),
    // Physical pixels: the decode target is what the device will rasterise, not
    // what the layout calls it.
    width: (diameter * devicePixelRatio).round(),
  );
}
