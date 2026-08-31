import 'dart:io';
import 'package:flame/models/user.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/models/photo.dart';
// Re-exported so callers importing this service keep resolving Photo; the
// model itself now lives in lib/models/, where a model belongs.
export 'package:flame/models/photo.dart' show Photo;

/// Builds the PATCH /users/me request body. The flame backend reads camelCase
/// (`lookingFor`); snake_case (`looking_for`) is included for forward-compat.
Map<String, dynamic> buildUpdateProfileBody({
  String? name,
  String? bio,
  List<String>? interests,
  Gender? lookingFor,
  Gender? gender,
  int? age,
  bool? termsAccepted,
  bool? profileComplete,
}) {
  final body = <String, dynamic>{};
  if (name != null) body['name'] = name;
  if (bio != null) body['bio'] = bio;
  if (interests != null) body['interests'] = interests;
  if (lookingFor != null) {
    body['lookingFor'] = lookingFor.toApiString();
    body['looking_for'] = lookingFor.toApiString();
  }
  if (gender != null) body['gender'] = gender.toApiString();
  if (age != null) body['age'] = age;
  // A social signup has no /auth/register call to carry its consent, and this
  // PATCH is the first request after the gate. Only ever sent as true — there
  // is no such thing as withdrawing consent by editing a bio.
  if (termsAccepted == true) body['termsAccepted'] = true;
  // Only ever true. Nothing should be able to un-complete a profile by editing
  // a bio, so false is silence rather than profileComplete: false.
  if (profileComplete == true) body['profileComplete'] = true;
  return body;
}

class UserService {
  final ApiClient _apiClient = ApiClient();

  // Get current user profile
  Future<ServiceResult<User>> getCurrentUser() async {
    final response = await _apiClient.get('/users/me');

    if (response.success && response.data != null) {
      final user = User.fromJson(response.data);
      return ServiceResult.success(user);
    }

    return ServiceResult.failure(response.error ?? 'Failed to get user');
  }

  // Get user by ID
  Future<ServiceResult<User>> getUserById(String userId) async {
    final response = await _apiClient.get('/users/$userId');

    if (response.success && response.data != null) {
      final user = User.fromJson(response.data);
      return ServiceResult.success(user);
    }

    return ServiceResult.failure(response.error ?? 'Failed to get user');
  }

  // Update profile
  Future<ServiceResult<User>> updateProfile({
    String? name,
    String? bio,
    List<String>? interests,
    Gender? lookingFor,
    Gender? gender,
    int? age,
    bool? termsAccepted,
    bool? profileComplete,
  }) async {
    final body = buildUpdateProfileBody(
      name: name,
      bio: bio,
      termsAccepted: termsAccepted,
      profileComplete: profileComplete,
      interests: interests,
      lookingFor: lookingFor,
      gender: gender,
      age: age,
    );

    final response = await _apiClient.patch('/users/me', body: body);

    if (response.success && response.data != null) {
      final user = User.fromJson(response.data);
      return ServiceResult.success(user);
    }

    return ServiceResult.failure(response.error ?? 'Failed to update profile');
  }

  // Update location
  Future<ServiceResult<Map<String, dynamic>>> updateLocation({
    required double latitude,
    required double longitude,
  }) async {
    final response = await _apiClient.patch('/users/me/location', body: {
      'latitude': latitude,
      'longitude': longitude,
    });

    if (response.success && response.data != null) {
      return ServiceResult.success(response.data['location'] ?? response.data);
    }

    return ServiceResult.failure(response.error ?? 'Failed to update location');
  }

  // Update preferences
  Future<ServiceResult<Map<String, dynamic>>> updatePreferences({
    int? minAge,
    int? maxAge,
    double? maxDistance,
    bool? showDistance,
    bool? showOnlineStatus,
    List<String>? interestsFilter,
  }) async {
    final body = <String, dynamic>{};
    if (minAge != null) body['min_age'] = minAge;
    if (maxAge != null) body['max_age'] = maxAge;
    if (maxDistance != null) body['max_distance'] = maxDistance;
    if (showDistance != null) body['show_distance'] = showDistance;
    if (showOnlineStatus != null) body['show_online_status'] = showOnlineStatus;
    if (interestsFilter != null) body['interests_filter'] = interestsFilter;

    final response = await _apiClient.patch('/users/me/preferences', body: body);

    if (response.success && response.data != null) {
      return ServiceResult.success(response.data['preferences'] ?? response.data);
    }

    return ServiceResult.failure(response.error ?? 'Failed to update preferences');
  }

  // Upload photo (for logged-in users)
  Future<ServiceResult<Photo>> uploadPhoto(File photo, {bool isPrimary = false}) async {
    final response = await _apiClient.uploadFile(
      '/users/me/photos',
      photo,
      fieldName: 'photo',
      fields: {'is_primary': isPrimary.toString()},
    );

    if (response.success && response.data != null) {
      return ServiceResult.success(Photo.fromJson(response.data));
    }

    return ServiceResult.failure(response.error ?? 'Failed to upload photo');
  }

  // Upload photo during registration (before logged in)
  // This uploads to a temporary storage and returns a URL
  Future<ServiceResult<Photo>> uploadPhotoForRegistration(File photo, {bool isPrimary = false}) async {
    final response = await _apiClient.uploadFile(
      '/auth/upload-photo',
      photo,
      fieldName: 'photo',
      queryParams: {'is_primary': isPrimary.toString()},
    );

    if (response.success && response.data != null) {
      return ServiceResult.success(Photo.fromJson(response.data));
    }

    return ServiceResult.failure(response.error ?? 'Failed to upload photo');
  }

  // Delete photo
  Future<ServiceResult<void>> deletePhoto(String photoId) async {
    final response = await _apiClient.delete('/users/me/photos/$photoId');

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to delete photo');
  }

  // Reorder photos
  Future<ServiceResult<List<Photo>>> reorderPhotos(List<String> photoIds) async {
    final response = await _apiClient.patch('/users/me/photos/reorder', body: {
      'photo_ids': photoIds,
    });

    if (response.success && response.data != null) {
      final photosData = response.data['photos'] as List? ?? [];
      final photos = photosData.map((p) => Photo.fromJson(p)).toList();
      return ServiceResult.success(photos);
    }

    return ServiceResult.failure(response.error ?? 'Failed to reorder photos');
  }

  // Delete account
  /// Deletes the account and its data.
  ///
  /// [password] is optional because a social-only signup has none — requiring
  /// it put the account deletion Google Play mandates out of reach for every
  /// Google user. The server enforces it for the accounts that do have one.
  Future<ServiceResult<void>> deleteAccount({
    String? password,
    String? reason,
  }) async {
    final body = <String, dynamic>{};
    if (password != null) body['password'] = password;
    if (reason != null) body['reason'] = reason;

    final response = await _apiClient.delete('/users/me', body: body);

    if (response.success) {
      await _apiClient.clearTokens();
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to delete account');
  }

}



// Generic service result
class ServiceResult<T> {
  final bool success;
  final T? data;
  final String? error;

  ServiceResult._({
    required this.success,
    this.data,
    this.error,
  });

  factory ServiceResult.success(T? data) {
    return ServiceResult._(success: true, data: data);
  }

  factory ServiceResult.failure(String error) {
    return ServiceResult._(success: false, error: error);
  }
}
