import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/providers/user_provider.dart';

class _FakeUserService extends UserService {
  bool deleteCalled = false;
  String? deletedId;
  List<String>? reorderedIds;
  bool reorderSucceeds = true;

  @override
  Future<ServiceResult<void>> deletePhoto(String photoId) async {
    deleteCalled = true;
    deletedId = photoId;
    return ServiceResult.success(null);
  }

  @override
  Future<ServiceResult<List<Photo>>> reorderPhotos(List<String> photoIds) async {
    reorderedIds = photoIds;
    if (!reorderSucceeds) return ServiceResult.failure('nope');
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
  _moveTests();

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

  test('setMainPhotoAt moves the chosen photo to the front', () async {
    final fake = _FakeUserService();
    final n = CurrentUserNotifier(fake)..setUser(_userWithPhotos());

    expect(await n.setMainPhotoAt(2), isTrue);

    expect(fake.reorderedIds, ['p3', 'p1', 'p2']);
    expect(n.state.value!.photoIds, ['p3', 'p1', 'p2']);
  });

  test('setMainPhotoAt on index 0 is a no-op', () async {
    final fake = _FakeUserService();
    final n = CurrentUserNotifier(fake)..setUser(_userWithPhotos());

    expect(await n.setMainPhotoAt(0), isFalse,
        reason: 'it is already the main photo; a request is not a change');
    expect(fake.reorderedIds, isNull, reason: 'and no request went out');
  });

  test('a failed reorder leaves the order alone', () async {
    final fake = _FakeUserService()..reorderSucceeds = false;
    final n = CurrentUserNotifier(fake)..setUser(_userWithPhotos());

    expect(await n.setMainPhotoAt(1), isFalse);
    expect(n.state.value!.photoIds, ['p1', 'p2', 'p3'],
        reason: 'an optimistic reorder that reverts on the next fetch looks '
            'like the app forgetting what you asked for');
  });
}

// movePhoto — the drag-to-reorder gesture in edit-profile.
//
// The route takes a full permutation and rejects a subset outright, because
// accepting one would silently delete the photos left out of it. So the whole
// contract here is "send every id, exactly once, in the new order".
void _moveTests() {
  test('movePhoto sends the full list in the new order', () async {
    final fake = _FakeUserService();
    final n = CurrentUserNotifier(fake)..setUser(_userWithPhotos());

    final ok = await n.movePhoto(2, 0);

    expect(ok, isTrue);
    expect(fake.reorderedIds, ['p3', 'p1', 'p2'],
        reason: 'a subset would delete the photos it omits');
    expect(n.state.value!.photos, ['url-p3', 'url-p1', 'url-p2']);
  });

  test('moving forward keeps every other photo in its relative order', () async {
    final fake = _FakeUserService();
    final n = CurrentUserNotifier(fake)..setUser(_userWithPhotos());

    await n.movePhoto(0, 2);

    expect(fake.reorderedIds, ['p2', 'p3', 'p1']);
  });

  test('the response is adopted, not the locally-guessed order', () async {
    // The server owns isPrimary and the canonical order. A client that keeps
    // its own guess drifts the moment the two disagree.
    final fake = _FakeUserService()..reorderSucceeds = true;
    final n = CurrentUserNotifier(fake)..setUser(_userWithPhotos());

    await n.movePhoto(1, 0);

    expect(n.state.value!.photoIds, fake.reorderedIds);
  });

  test('a failed reorder leaves the order untouched', () async {
    final fake = _FakeUserService()..reorderSucceeds = false;
    final n = CurrentUserNotifier(fake)..setUser(_userWithPhotos());

    final ok = await n.movePhoto(2, 0);

    expect(ok, isFalse);
    expect(n.state.value!.photoIds, ['p1', 'p2', 'p3'],
        reason: 'the grid must not show an order the server refused');
  });

  test('a no-op move never reaches the network', () async {
    final fake = _FakeUserService();
    final n = CurrentUserNotifier(fake)..setUser(_userWithPhotos());

    expect(await n.movePhoto(1, 1), isFalse);
    expect(fake.reorderedIds, isNull, reason: 'the route rejects a no-op');
  });

  test('an out-of-range index never reaches the network', () async {
    final fake = _FakeUserService();
    final n = CurrentUserNotifier(fake)..setUser(_userWithPhotos());

    expect(await n.movePhoto(0, 9), isFalse);
    expect(await n.movePhoto(-1, 0), isFalse);
    expect(fake.reorderedIds, isNull);
  });

  test('a photo with no id blocks the whole reorder', () async {
    // An id-less photo would be sent as '', which the route reads as an
    // unknown id and rejects — after the user has already seen the drag land.
    final fake = _FakeUserService();
    final u = User.fromJson({
      'id': 'u1', 'name': 'A', 'age': 20, 'bio': '', 'interests': [],
      'gender': 'female', 'photos': ['bare-url', 'other-url'],
    });
    final n = CurrentUserNotifier(fake)..setUser(u);

    expect(await n.movePhoto(1, 0), isFalse);
    expect(fake.reorderedIds, isNull);
  });
}
