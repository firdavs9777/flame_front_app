import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';

void main() {
  group('User.fromJson photos', () {
    test('parses objects with variants', () {
      final user = User.fromJson({
        'id': 'u1',
        'name': 'Ada',
        'photos': [
          {
            'id': 'p1',
            'url': 'https://cdn/a.jpg',
            'url_thumb': 'https://cdn/a-thumb.webp',
          },
        ],
      });

      expect(user.photos, hasLength(1));
      expect(user.photos.first.id, 'p1');
      expect(user.photos.first.urlThumb, 'https://cdn/a-thumb.webp');
    });

    test('parses bare URL strings', () {
      final user = User.fromJson({
        'id': 'u1',
        'name': 'Ada',
        'photos': ['https://cdn/a.jpg'],
      });
      expect(user.photos.first.url, 'https://cdn/a.jpg');
    });

    test('drops entries with no usable url', () {
      final user = User.fromJson({
        'id': 'u1',
        'name': 'Ada',
        'photos': [
          {'id': 'p1'},
          {'id': 'p2', 'url': 'https://cdn/b.jpg'},
          42,
        ],
      });
      expect(user.photos, hasLength(1));
      expect(user.photos.first.id, 'p2');
    });

    test('photoIds stays available and stays aligned', () {
      final user = User.fromJson({
        'id': 'u1',
        'name': 'Ada',
        'photos': [
          {'id': 'p1', 'url': 'https://cdn/a.jpg'},
          {'id': 'p2', 'url': 'https://cdn/b.jpg'},
        ],
      });
      expect(user.photoIds, ['p1', 'p2']);
    });

    test('handles a missing photos key', () {
      final user = User.fromJson({'id': 'u1', 'name': 'Ada'});
      expect(user.photos, isEmpty);
      expect(user.photoIds, isEmpty);
    });

    test('primaryPhoto is null rather than an empty-url photo', () {
      final user = User.fromJson({'id': 'u1', 'name': 'Ada'});
      expect(user.primaryPhoto, isNull);
    });
  });
}
