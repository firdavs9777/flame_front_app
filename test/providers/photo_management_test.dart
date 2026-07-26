import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/providers/user_provider.dart';

class _FakeUserService extends UserService {
  bool deleteCalled = false;
  String? deletedId;
  List<String>? reorderedIds;

  @override
  Future<ServiceResult<void>> deletePhoto(String photoId) async {
    deleteCalled = true;
    deletedId = photoId;
    return ServiceResult.success(null);
  }

  @override
  Future<ServiceResult<List<Photo>>> reorderPhotos(List<String> photoIds) async {
    reorderedIds = photoIds;
    // Echo back the requested order as Photo objects.
    final photos = <Photo>[];
    for (var i = 0; i < photoIds.length; i++) {
      photos.add(Photo(id: photoIds[i], url: 'url-${photoIds[i]}', order: i));
    }
    return ServiceResult.success(photos);
  }
}

User _userWithPhotos() => User.fromJson({
      'id': 'u1',
      'name': 'Ann',
      'age': 27,
      'bio': '',
      'interests': <dynamic>[],
      'gender': 'female',
      'photos': [
        {'id': 'p1', 'url': 'url-p1'},
        {'id': 'p2', 'url': 'url-p2'},
        {'id': 'p3', 'url': 'url-p3'},
      ],
    });

void main() {
  test('deletePhotoAt removes the photo + id at that index on success', () async {
    final fake = _FakeUserService();
    final n = CurrentUserNotifier(fake)..setUser(_userWithPhotos());

    final ok = await n.deletePhotoAt(1);

    expect(ok, isTrue);
    expect(fake.deletedId, 'p2');
    expect(n.state.value!.photoIds, ['p1', 'p3']);
    expect(n.state.value!.photos, ['url-p1', 'url-p3']);
  });

  test('deletePhotoAt returns false for an unknown/empty id', () async {
    final fake = _FakeUserService();
    final u = User.fromJson({
      'id': 'u1', 'name': 'A', 'age': 20, 'bio': '', 'interests': [],
      'gender': 'female', 'photos': ['bare-url'], // id == ''
    });
    final n = CurrentUserNotifier(fake)..setUser(u);

    final ok = await n.deletePhotoAt(0);

    expect(ok, isFalse);
    expect(fake.deleteCalled, isFalse);
  });

  test('setMainPhotoAt reorders selected id to the front', () async {
    final fake = _FakeUserService();
    final n = CurrentUserNotifier(fake)..setUser(_userWithPhotos());

    final ok = await n.setMainPhotoAt(2);

    expect(ok, isTrue);
    expect(fake.reorderedIds, ['p3', 'p1', 'p2']);
    expect(n.state.value!.photoIds, ['p3', 'p1', 'p2']);
    expect(n.state.value!.photos, ['url-p3', 'url-p1', 'url-p2']);
  });
}
