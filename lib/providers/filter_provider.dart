import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/core/interests/interest_catalogue.dart';
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
      interests: user.interestsFilter,
    );
  }

  /// Adds or removes [token], refusing to exceed [kMaxInterestFilter] — the
  /// backend rejects a longer list, so the UI must not offer one.
  void toggleInterest(String token) {
    final next = [...state.interests];
    if (next.remove(token)) {
      state = state.copyWith(interests: next);
      return;
    }
    if (next.length >= kMaxInterestFilter) return;
    state = state.copyWith(interests: [...next, token]);
  }

  /// Saves every filter, and reports whether all of it landed.
  ///
  /// Gender is `lookingFor` on the profile rather than a preference: the discovery
  /// query already reads that field, and a second field meaning the same thing
  /// would disagree with it.
  Future<bool> savePreferencesToApi() async {
    final prefs = await _userService.updatePreferences(
      minAge: state.minAge,
      maxAge: state.maxAge,
      maxDistance: state.maxDistance,
      interestsFilter: state.interests,
    );
    if (!prefs.success) return false;

    final gender = state.genderPreference;
    if (gender == null) return true;
    final profile = await _userService.updateProfile(lookingFor: gender);
    return profile.success;
  }
}

class DiscoveryFilters {
  final int minAge;
  final int maxAge;
  final double maxDistance;
  final Gender? genderPreference;
  final List<String> interests;

  const DiscoveryFilters({
    this.minAge = 18,
    this.maxAge = 50,
    this.maxDistance = 50,
    this.genderPreference,
    this.interests = const [],
  });

  DiscoveryFilters copyWith({
    int? minAge,
    int? maxAge,
    double? maxDistance,
    Gender? genderPreference,
    List<String>? interests,
  }) {
    return DiscoveryFilters(
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      maxDistance: maxDistance ?? this.maxDistance,
      genderPreference: genderPreference ?? this.genderPreference,
      interests: interests ?? this.interests,
    );
  }
}
