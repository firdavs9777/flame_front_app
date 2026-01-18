import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/user_service.dart';

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
      state = AsyncValue.error(result.error ?? 'Failed to load user', StackTrace.current);
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
        photos: [...currentUser.photos, result.data!.url],
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

  Future<bool> updateLocation(double latitude, double longitude) async {
    final result = await _userService.updateLocation(
      latitude: latitude,
      longitude: longitude,
    );
    return result.success;
  }
}
