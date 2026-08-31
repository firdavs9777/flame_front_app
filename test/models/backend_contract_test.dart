import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/image/photo_variants.dart';
import 'package:flame/models/photo.dart';

/// The exact JSON the Flame backend emits, captured from
/// `flame/utils/photoShape.js` `toPhoto`. If the server's shape drifts, this
/// test is the one that should fail — not a user's blank profile.
const String backendPhotoJson =
    '{"id":"p1","url":"https://cdn/a.jpg","url_medium":"https://cdn/m.webp",'
    '"url_thumb":"https://cdn/t.webp","is_primary":true,"isPrimary":true,"order":0}';

/// What the backend emits for a photo that predates the variant pipeline:
/// the keys are present and null, never absent.
const String backendLegacyPhotoJson =
    '{"id":"p2","url":"https://cdn/b.jpg","url_medium":null,"url_thumb":null,'
    '"is_primary":false,"isPrimary":false,"order":1}';

void main() {
  group('backend photo contract', () {
    test('parses the server shape, variants included', () {
      final photo = Photo.fromJson(jsonDecode(backendPhotoJson));

      expect(photo.id, 'p1');
      expect(photo.url, 'https://cdn/a.jpg');
      expect(photo.urlMedium, 'https://cdn/m.webp');
      expect(photo.urlThumb, 'https://cdn/t.webp');
      expect(photo.isPrimary, isTrue);
      expect(photo.order, 0);
    });

    test('picks the thumb for an avatar and the full for a card', () {
      final photo = Photo.fromJson(jsonDecode(backendPhotoJson));
      expect(photoUrlFor(photo, PhotoSize.thumb), 'https://cdn/t.webp');
      expect(photoUrlFor(photo, PhotoSize.medium), 'https://cdn/m.webp');
      expect(photoUrlFor(photo, PhotoSize.full), 'https://cdn/a.jpg');
    });

    test('a photo the backfill has not reached falls back to the original', () {
      final photo = Photo.fromJson(jsonDecode(backendLegacyPhotoJson));
      expect(photo.urlThumb, isNull);
      // Slow, but never broken.
      expect(photoUrlFor(photo, PhotoSize.thumb), 'https://cdn/b.jpg');
    });

    test('null variant keys do not become the string "null"', () {
      // jsonDecode yields a real null; `raw[key]?.toString()` must not turn it
      // into "null" and hand the image layer a bogus URL.
      final photo = Photo.fromJson(jsonDecode(backendLegacyPhotoJson));
      expect(photo.urlMedium, isNot('null'));
      expect(photo.urlThumb, isNot('null'));
    });
  });
}
