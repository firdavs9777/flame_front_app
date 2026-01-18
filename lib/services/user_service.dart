import 'dart:io';
import 'package:flame/models/user.dart';
import 'package:flame/services/api_client.dart';

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
    int? age,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (bio != null) body['bio'] = bio;
    if (interests != null) body['interests'] = interests;
    if (lookingFor != null) body['looking_for'] = lookingFor.toApiString();
    if (age != null) body['age'] = age;

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
  }) async {
    final body = <String, dynamic>{};
    if (minAge != null) body['min_age'] = minAge;
    if (maxAge != null) body['max_age'] = maxAge;
    if (maxDistance != null) body['max_distance'] = maxDistance;
    if (showDistance != null) body['show_distance'] = showDistance;
    if (showOnlineStatus != null) body['show_online_status'] = showOnlineStatus;

    final response = await _apiClient.patch('/users/me/preferences', body: body);

    if (response.success && response.data != null) {
      return ServiceResult.success(response.data['preferences'] ?? response.data);
    }

    return ServiceResult.failure(response.error ?? 'Failed to update preferences');
  }

  // Update notification settings
  Future<ServiceResult<Map<String, dynamic>>> updateNotificationSettings({
    bool? newMatches,
    bool? newMessages,
    bool? superLikes,
    bool? promotions,
  }) async {
    final body = <String, dynamic>{};
    if (newMatches != null) body['new_matches'] = newMatches;
    if (newMessages != null) body['new_messages'] = newMessages;
    if (superLikes != null) body['super_likes'] = superLikes;
    if (promotions != null) body['promotions'] = promotions;

    final response = await _apiClient.patch('/users/me/notifications', body: body);

    if (response.success && response.data != null) {
      return ServiceResult.success(response.data['notifications'] ?? response.data);
    }

    return ServiceResult.failure(response.error ?? 'Failed to update notification settings');
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
      fields: {'is_primary': isPrimary.toString()},
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
  Future<ServiceResult<void>> deleteAccount({
    required String password,
    String? reason,
  }) async {
    final body = <String, dynamic>{
      'password': password,
    };
    if (reason != null) body['reason'] = reason;

    final response = await _apiClient.delete('/users/me', body: body);

    if (response.success) {
      await _apiClient.clearTokens();
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to delete account');
  }

  // Register device for push notifications
  Future<ServiceResult<void>> registerDevice({
    required String token,
    required String platform,
  }) async {
    final response = await _apiClient.post('/devices', body: {
      'token': token,
      'platform': platform,
    });

    if (response.success) {
      return ServiceResult.success(null);
    }

    return ServiceResult.failure(response.error ?? 'Failed to register device');
  }
}

// Photo model
class Photo {
  final String id;
  final String url;
  final bool isPrimary;
  final int order;

  Photo({
    required this.id,
    required this.url,
    this.isPrimary = false,
    this.order = 0,
  });

  factory Photo.fromJson(Map<String, dynamic> json) {
    return Photo(
      id: json['id'] ?? '',
      url: json['url'] ?? '',
      isPrimary: json['is_primary'] ?? false,
      order: json['order'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'is_primary': isPrimary,
      'order': order,
    };
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
