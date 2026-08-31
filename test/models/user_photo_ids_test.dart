import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';
import 'package:flame/models/photo.dart';

Map<String, dynamic> _base(List photos) => {
      'id': 'u1',
      'name': 'Ann',
      'age': 27,
      'bio': '',
      'interests': <dynamic>[],
      'gender': 'female',
      'photos': photos,
    };

void main() {
  test('fromJson parses photo objects into aligned photos + photoIds', () {
    final u = User.fromJson(_base([
      {'id': 'p1', 'url': 'https://x/1.jpg'},
      {'id': 'p2', 'url': 'https://x/2.jpg'},
    ]));
    expect(u.photos.map((p) => p.url).toList(), ['https://x/1.jpg', 'https://x/2.jpg']);
    expect(u.photoIds, ['p1', 'p2']);
  });

  test('bare string photos yield empty ids, still aligned', () {
    final u = User.fromJson(_base(['https://x/a.jpg']));
    expect(u.photos.map((p) => p.url).toList(), ['https://x/a.jpg']);
    expect(u.photoIds, ['']);
  });

  test('entries with empty url are dropped from BOTH lists (stay aligned)', () {
    final u = User.fromJson(_base([
      {'id': 'p1', 'url': ''},
      {'id': 'p2', 'url': 'https://x/2.jpg'},
    ]));
    expect(u.photos.map((p) => p.url).toList(), ['https://x/2.jpg']);
    expect(u.photoIds, ['p2']);
  });

  test('photoIds defaults to empty list when absent', () {
    final u = User.fromJson(_base(<dynamic>[]));
    expect(u.photoIds, isEmpty);
  });

  test('copyWith carries ids along with the photos they belong to', () {
    // photoIds used to be its own list that copyWith could replace
    // independently, which meant a caller could put the two out of step. It is
    // derived now, so replacing the photos is the only way to change the ids.
    final u = User.fromJson(_base(<dynamic>[])).copyWith(
      photos: const [Photo(id: 'x', url: 'https://cdn/a.jpg')],
    );
    expect(u.photoIds, ['x']);
  });
}
