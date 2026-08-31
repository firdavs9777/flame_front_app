import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/core/i18n/error_strings_for.dart';

final userServiceProvider = Provider<UserService>((ref) => UserService());

// Current user provider with async loading from API
final currentUserProvider = StateNotifierProvider<CurrentUserNotifier, AsyncValue<User?>>((ref) {
  return CurrentUserNotifier(ref.watch(userServiceProvider));
});

class CurrentUserNotifier extends StateNotifier<AsyncValue<User?>> {
  final UserService _userService;

  CurrentUserNotifier(this._userService) : super(const AsyncValue.loading());

  Future<void> loadUser() async {
    state = const AsyncValue.loading();
    final result = await _userService.getCurrentUser();
    if (result.success && result.data != null) {
      state = AsyncValue.data(result.data);
    } else {
      state = AsyncValue.error(ErrorStringsFor.fromString(result.error), StackTrace.current);
    }
  }

  void setUser(User user) {
    state = AsyncValue.data(user);
  }

  void clearUser() {
    state = const AsyncValue.data(null);
  }

  Future<bool> updateProfile({
    String? name,
    int? age,
    String? bio,
    List<String>? interests,
    Gender? lookingFor,
  }) async {
    final currentUser = state.valueOrNull;
    if (currentUser == null) return false;

    final result = await _userService.updateProfile(
      name: name,
      age: age,
      bio: bio,
      interests: interests,
      lookingFor: lookingFor,
    );

    if (result.success && result.data != null) {
      state = AsyncValue.data(result.data);
      return true;
    }
    return false;
  }

  Future<bool> updatePreferences({
    int? minAge,
    int? maxAge,
    double? maxDistance,
    bool? showDistance,
    bool? showOnlineStatus,
  }) async {
    final currentUser = state.valueOrNull;
    if (currentUser == null) return false;

    final result = await _userService.updatePreferences(
      minAge: minAge,
      maxAge: maxAge,
      maxDistance: maxDistance,
      showDistance: showDistance,
      showOnlineStatus: showOnlineStatus,
    );

    if (result.success) {
      // Update local state with new preferences
      state = AsyncValue.data(currentUser.copyWith(
        minAgePreference: minAge ?? currentUser.minAgePreference,
        maxAgePreference: maxAge ?? currentUser.maxAgePreference,
        maxDistancePreference: maxDistance ?? currentUser.maxDistancePreference,
        showDistance: showDistance ?? currentUser.showDistance,
        showOnlineStatus: showOnlineStatus ?? currentUser.showOnlineStatus,
      ));
      return true;
    }
    return false;
  }

  Future<bool> uploadPhoto(File photo, {bool isPrimary = false}) async {
    final currentUser = state.valueOrNull;
    if (currentUser == null) return false;

    final result = await _userService.uploadPhoto(photo, isPrimary: isPrimary);
    if (result.success && result.data != null) {
      state = AsyncValue.data(currentUser.copyWith(
        photos: [...currentUser.photos, result.data!],
      ));
      return true;
    }
    return false;
  }

  Future<bool> deletePhoto(String photoId) async {
    final currentUser = state.valueOrNull;
    if (currentUser == null) return false;

    final result = await _userService.deletePhoto(photoId);
    if (result.success) {
      // Reload user to get updated photos
      await loadUser();
      return true;
    }
    return false;
  }

  /// Deletes the photo at [index] by its backend id and updates local state.
  Future<bool> deletePhotoAt(int index) async {
    final currentUser = state.valueOrNull;
    if (currentUser == null) return false;
    if (index < 0 || index >= currentUser.photoIds.length) return false;
    final photoId = currentUser.photoIds[index];
    if (photoId.isEmpty) return false;

    final result = await _userService.deletePhoto(photoId);
    if (!result.success) return false;

    final photos = [...currentUser.photos]..removeAt(index);
    final ids = [...currentUser.photoIds]..removeAt(index);
    state = AsyncValue.data(currentUser.copyWith(photos: photos));
    return true;
  }

  /// Moves the photo at [from] to sit at [to], keeping every other photo's
  /// relative order.
  ///
  /// The route takes a full permutation, never a subset: it rejects one
  /// outright rather than silently deleting the photos left out. So this sends
  /// the whole list, reordered locally, and adopts whatever comes back — the
  /// server owns `isPrimary`, which moves to whichever photo ends up first.
  Future<bool> movePhoto(int from, int to) async {
    final currentUser = state.valueOrNull;
    if (currentUser == null) return false;

    final ids = [...currentUser.photoIds];
    if (from < 0 || from >= ids.length) return false;
    if (to < 0 || to >= ids.length) return false;
    if (from == to) return false;
    if (ids.any((id) => id.isEmpty)) return false;

    ids.insert(to, ids.removeAt(from));

    final result = await _userService.reorderPhotos(ids);
    if (!result.success || result.data == null) return false;

    final photos = result.data!;
    state = AsyncValue.data(currentUser.copyWith(
      photos: photos,
    ));
    return true;
  }

  /// Makes the photo at [index] the main photo by reordering it to the front.
  Future<bool> setMainPhotoAt(int index) async {
    final currentUser = state.valueOrNull;
    if (currentUser == null) return false;
    if (index <= 0 || index >= currentUser.photoIds.length) return false;
    final id = currentUser.photoIds[index];
    if (id.isEmpty) return false;

    final ids = [...currentUser.photoIds];
    ids.removeAt(index);
    ids.insert(0, id);

    final result = await _userService.reorderPhotos(ids);
    if (!result.success || result.data == null) return false;

    final photos = result.data!;
    state = AsyncValue.data(currentUser.copyWith(
      photos: photos,
    ));
    return true;
  }

  Future<bool> updateLocation(double latitude, double longitude) async {
    final result = await _userService.updateLocation(
      latitude: latitude,
      longitude: longitude,
    );
    return result.success;
  }

  /// Deletes the account via the API. On success clears the local user; the
  /// caller is responsible for logging out / routing away. Returns false on
  /// failure (e.g. wrong password) with state unchanged.
  /// Deletes the account. Returns null on success, or the server's reason.
  ///
  /// Was a bare bool, so every failure surfaced as "Could not delete account.
  /// Check your password." — advice that is actively wrong for a social
  /// account, which has no password, and which hid whatever the server
  /// actually said.
  Future<String?> deleteAccount({String? password}) async {
    final result = await _userService.deleteAccount(password: password);
    if (result.success) {
      clearUser();
      return null;
    }
    return result.error ?? '';
  }
}
