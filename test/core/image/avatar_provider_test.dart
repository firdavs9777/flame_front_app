import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/image/avatar_provider.dart';
import 'package:flame/models/photo.dart';

Photo _photo({String? thumb}) =>
    Photo(id: 'p1', url: 'https://cdn/full.jpg', urlThumb: thumb);

void main() {
  test('returns null for a photo-less user', () {
    expect(avatarProviderFor(null, diameter: 64, devicePixelRatio: 3), isNull);
  });

  test('resizes to the physical diameter', () {
    final provider = avatarProviderFor(
      _photo(thumb: 'https://cdn/t.webp'),
      diameter: 64,
      devicePixelRatio: 3,
    );
    expect(provider, isA<ResizeImage>());
    expect((provider! as ResizeImage).width, 192);
  });

  test('prefers the thumb variant', () {
    final provider = avatarProviderFor(
      _photo(thumb: 'https://cdn/t.webp'),
      diameter: 64,
      devicePixelRatio: 1,
    ) as ResizeImage;
    expect(provider.imageProvider.toString(), contains('t.webp'));
  });

  test('falls back to the full image when no variant exists', () {
    final provider = avatarProviderFor(
      _photo(),
      diameter: 64,
      devicePixelRatio: 1,
    ) as ResizeImage;
    expect(provider.imageProvider.toString(), contains('full.jpg'));
  });
}
