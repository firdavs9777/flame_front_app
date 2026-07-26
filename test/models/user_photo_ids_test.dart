import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';

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
    expect(u.photos, ['https://x/1.jpg', 'https://x/2.jpg']);
    expect(u.photoIds, ['p1', 'p2']);
  });

  test('bare string photos yield empty ids, still aligned', () {
    final u = User.fromJson(_base(['https://x/a.jpg']));
    expect(u.photos, ['https://x/a.jpg']);
    expect(u.photoIds, ['']);
  });

  test('entries with empty url are dropped from BOTH lists (stay aligned)', () {
    final u = User.fromJson(_base([
      {'id': 'p1', 'url': ''},
      {'id': 'p2', 'url': 'https://x/2.jpg'},
    ]));
    expect(u.photos, ['https://x/2.jpg']);
    expect(u.photoIds, ['p2']);
  });

  test('photoIds defaults to empty list when absent', () {
    final u = User.fromJson(_base(<dynamic>[]));
    expect(u.photoIds, isEmpty);
  });

  test('copyWith replaces photoIds', () {
    final u = User.fromJson(_base(<dynamic>[])).copyWith(
      photos: ['a'],
      photoIds: ['x'],
    );
    expect(u.photoIds, ['x']);
  });
}
