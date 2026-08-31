import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/image/photo_variants.dart';
import 'package:flame/models/photo.dart';

Photo _photo({String? medium, String? thumb}) => Photo(
      id: 'p1',
      url: 'https://cdn/full.jpg',
      urlMedium: medium,
      urlThumb: thumb,
    );

void main() {
  group('photoUrlFor', () {
    test('picks the exact variant when it exists', () {
      final photo = _photo(medium: 'https://cdn/m.webp', thumb: 'https://cdn/t.webp');
      expect(photoUrlFor(photo, PhotoSize.thumb), 'https://cdn/t.webp');
      expect(photoUrlFor(photo, PhotoSize.medium), 'https://cdn/m.webp');
      expect(photoUrlFor(photo, PhotoSize.full), 'https://cdn/full.jpg');
    });

    test('falls back down the ladder, never up', () {
      // A photo the backfill has not reached yet. Serving the full image is
      // slow; serving nothing is broken.
      final photo = _photo(medium: 'https://cdn/m.webp');
      expect(photoUrlFor(photo, PhotoSize.thumb), 'https://cdn/m.webp');
    });

    test('falls all the way back to the original', () {
      final photo = _photo();
      expect(photoUrlFor(photo, PhotoSize.thumb), 'https://cdn/full.jpg');
      expect(photoUrlFor(photo, PhotoSize.medium), 'https://cdn/full.jpg');
    });

    test('treats an empty variant as absent', () {
      final photo = _photo(thumb: '');
      expect(photoUrlFor(photo, PhotoSize.thumb), 'https://cdn/full.jpg');
    });
  });
}
