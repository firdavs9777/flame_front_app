import 'package:flame/models/photo.dart';

/// The variant to request. Named for the surface, not the pixel count, so call
/// sites read as intent rather than as a number to second-guess.
enum PhotoSize {
  /// 256px long edge — avatars, matches grid, chat rows.
  thumb,

  /// 512px long edge — edit-profile grid, previews.
  medium,

  /// 1440px long edge — deck cards, profile detail, gallery, media viewer.
  full,
}

/// The best available URL at or above [size].
///
/// Falls back down the ladder — thumb to medium to full — never up. A photo the
/// backfill has not reached yet has no variants at all, and serving a slow
/// image beats serving a broken one.
String photoUrlFor(Photo photo, PhotoSize size) {
  // Empty counts as absent as well as null. Photo.tryFromJson already
  // normalises what arrives from the server, but a Photo can also be built
  // directly, and an empty string is not a URL under any reading.
  String? present(String? url) => (url == null || url.isEmpty) ? null : url;

  final thumb = present(photo.urlThumb);
  final medium = present(photo.urlMedium);

  return switch (size) {
    PhotoSize.thumb => thumb ?? medium ?? photo.url,
    PhotoSize.medium => medium ?? photo.url,
    PhotoSize.full => photo.url,
  };
}
