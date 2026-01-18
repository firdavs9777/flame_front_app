import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/services/user_service.dart';

final filterProvider = StateNotifierProvider<FilterNotifier, DiscoveryFilters>((ref) {
  return FilterNotifier();
});

class FilterNotifier extends StateNotifier<DiscoveryFilters> {
  final UserService _userService = UserService();

  FilterNotifier() : super(const DiscoveryFilters());

  void setAgeRange(int min, int max) {
    state = state.copyWith(minAge: min, maxAge: max);
  }

  void setMaxDistance(double distance) {
    state = state.copyWith(maxDistance: distance);
  }

  void setGenderPreference(Gender? gender) {
    state = state.copyWith(genderPreference: gender);
  }

  void setInterests(List<String> interests) {
    state = state.copyWith(interests: interests);
  }

  void toggleOnlineOnly() {
    state = state.copyWith(onlineOnly: !state.onlineOnly);
  }

  void reset() {
    state = const DiscoveryFilters();
  }

  /// Initialize filters from user preferences
  void initFromUser(User user) {
    state = DiscoveryFilters(
      minAge: user.minAgePreference,
      maxAge: user.maxAgePreference,
      maxDistance: user.maxDistancePreference,
      genderPreference: user.lookingFor,
    );
  }

  /// Save preferences to API and return success status
  Future<bool> savePreferencesToApi() async {
    final result = await _userService.updatePreferences(
      minAge: state.minAge,
      maxAge: state.maxAge,
      maxDistance: state.maxDistance,
    );
    return result.success;
  }
}

class DiscoveryFilters {
  final int minAge;
  final int maxAge;
  final double maxDistance;
  final Gender? genderPreference;
  final List<String> interests;
  final bool onlineOnly;

  const DiscoveryFilters({
    this.minAge = 18,
    this.maxAge = 50,
    this.maxDistance = 50,
    this.genderPreference,
    this.interests = const [],
    this.onlineOnly = false,
  });

  DiscoveryFilters copyWith({
    int? minAge,
    int? maxAge,
    double? maxDistance,
    Gender? genderPreference,
    List<String>? interests,
    bool? onlineOnly,
  }) {
    return DiscoveryFilters(
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      maxDistance: maxDistance ?? this.maxDistance,
      genderPreference: genderPreference ?? this.genderPreference,
      interests: interests ?? this.interests,
      onlineOnly: onlineOnly ?? this.onlineOnly,
    );
  }
}
