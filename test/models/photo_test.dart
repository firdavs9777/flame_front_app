import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/photo.dart';

void main() {
  group('Photo.fromJson', () {
    test('reads a full object with variants', () {
      final photo = Photo.fromJson({
        'id': 'p1',
        'url': 'https://cdn/a.jpg',
        'url_medium': 'https://cdn/a-medium.webp',
        'url_thumb': 'https://cdn/a-thumb.webp',
        'is_primary': true,
        'order': 2,
      });

      expect(photo.id, 'p1');
      expect(photo.url, 'https://cdn/a.jpg');
      expect(photo.urlMedium, 'https://cdn/a-medium.webp');
      expect(photo.urlThumb, 'https://cdn/a-thumb.webp');
      expect(photo.isPrimary, isTrue);
      expect(photo.order, 2);
    });

    test('reads an object that predates variants', () {
      final photo = Photo.fromJson({'id': 'p1', 'url': 'https://cdn/a.jpg'});
      expect(photo.urlMedium, isNull);
      expect(photo.urlThumb, isNull);
    });

    test('treats a null variant from the server as absent', () {
      // to_public_dict always emits the keys, null when the photo predates
      // the backfill.
      final photo = Photo.fromJson({
        'id': 'p1',
        'url': 'https://cdn/a.jpg',
        'url_medium': null,
        'url_thumb': null,
      });
      expect(photo.urlThumb, isNull);
    });

    test('reads a bare URL string', () {
      final photo = Photo.fromJson('https://cdn/a.jpg');
      expect(photo.url, 'https://cdn/a.jpg');
      expect(photo.id, isEmpty);
    });

    test('returns null for an entry with no usable url', () {
      expect(Photo.tryFromJson({'id': 'p1'}), isNull);
      expect(Photo.tryFromJson({'id': 'p1', 'url': ''}), isNull);
      expect(Photo.tryFromJson(42), isNull);
      expect(Photo.tryFromJson(''), isNull);
    });
  });
}
