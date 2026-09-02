import 'package:flame/models/photo.dart';
/// Null for a missing, null, or zero distance — see [User.distance].
double? _parseDistance(Object? raw) {
  final value = (raw as num?)?.toDouble();
  if (value == null || value == 0) return null;
  return value;
}

class User {
  final String id;
  final String? email;
  final String name;
  final int age;
  final String bio;
  final List<Photo> photos;

  /// Backend photo ids, in photo order.
  ///
  /// Derived rather than stored: it used to be a second list held in step with
  /// [photos], which is a class of bug this removes rather than manages.
  List<String> get photoIds => photos.map((p) => p.id).toList();
  final String location;
  /// Kilometres to this user, or null when unknown — either side missing a
  /// location, or this user having turned `showDistance` off.
  ///
  /// No formatter here on purpose: rendering it needs localisations and a locale,
  /// which are a widget's business, not a model's. Callers use
  /// `formatDistanceAway` from core/format/distance_display.dart.
  final double? distance;
  final List<String> interests;

  /// Languages this person speaks, as ISO 639-1 codes.
  ///
  /// Empty means UNKNOWN, never "speaks nothing" — every account created
  /// before this feature has an empty list, and the ranker scores unknown
  /// neutrally rather than last.
  final List<String> languagesSpoken;

  /// Languages this person is learning, as ISO 639-1 codes.
  final List<String> languagesLearning;
  final Gender gender;
  final Gender lookingFor;
  final int minAgePreference;
  final int maxAgePreference;
  final double maxDistancePreference;
  final bool showDistance;

  /// The tokens this user filters Discover by — NOT their own [interests].
  /// Empty means no interest filter.
  final List<String> interestsFilter;
  final bool showOnlineStatus;
  final DateTime lastActive;
  final bool isOnline;
  final bool isVerified;
  final DateTime? createdAt;
  final List<String>? commonInterests;
  final bool isPremium;
  final DateTime? premiumExpiresAt;
  final int superLikesRemaining;
  // Server-evaluated profile completeness. Null when the backend hasn't
  // returned the field (e.g., during the deploy window or for old API
  // versions) — callers should fall back to a local heuristic in that case.
  final bool? isProfileComplete;

  /// When this account accepted the Terms and Privacy Policy, or null if it
  /// never has. Null is the normal state for every account created before
  /// consent was recorded, and for every social signup made while the checkbox
  /// existed only on the email path — those users are asked once on next open.
  final DateTime? termsAcceptedAt;
  /// Whether this account can be asked to confirm with a password.
  ///
  /// False for a social-only signup, which has none — the delete-account
  /// dialog must not demand one there. Self-view payloads only; defaults to
  /// true when the backend omits it, so a password account keeps its prompt.
  final bool hasPassword;
  // BCP 47 short form (e.g. "en", "es", "pt-BR"). Null when the user hasn't
  // explicitly picked a language in app settings.
  /// Which language the server will EMAIL this user in.
  ///
  /// Read `preferred_language` until now — a key the server has never sent. It
  /// parsed to null on every response, so nothing downstream could have worked.
  /// The field is `locale`.
  final String? locale;

  const User({
    required this.id,
    this.email,
    required this.name,
    required this.age,
    required this.bio,
    required this.photos,
    required this.location,
    this.distance,
    required this.interests,
    this.languagesSpoken = const [],
    this.languagesLearning = const [],
    required this.gender,
    required this.lookingFor,
    this.minAgePreference = 18,
    this.maxAgePreference = 50,
    this.maxDistancePreference = 50,
    this.showDistance = true,
    this.interestsFilter = const [],
    this.showOnlineStatus = true,
    required this.lastActive,
    this.isOnline = false,
    this.isVerified = false,
    this.createdAt,
    this.commonInterests,
    this.isPremium = false,
    this.premiumExpiresAt,
    this.superLikesRemaining = 3,
    this.isProfileComplete,
    this.termsAcceptedAt,
    this.hasPassword = true,
    this.locale,
  });

  /// Whether premium is active right now: `isPremium` is true AND
  /// `premiumExpiresAt` is null (no expiry) or still in the future.
  ///
  /// This rule is money-relevant — a lapsed subscription reading as active
  /// is the one failure worth getting wrong here — and it had already
  /// drifted into two separate call sites (a swipe-undo gate and the
  /// profile header) each re-deriving the same two fields. It lives on the
  /// model, next to the fields it reads, so every caller asks this one
  /// question instead of writing its own copy that can quietly disagree.
  bool get isPremiumActive {
    if (!isPremium) return false;
    if (premiumExpiresAt != null && premiumExpiresAt!.isBefore(DateTime.now())) {
      return false;
    }
    return true;
  }

  factory User.fromJson(Map<String, dynamic> json) {
    // Entries can be objects or bare URL strings; those with no usable URL
    // are dropped rather than kept as an empty-URL photo that fails later at
    // the image layer.
    final rawPhotos = json['photos'];
    final photos = rawPhotos is List
        ? rawPhotos.map(Photo.tryFromJson).whereType<Photo>().toList()
        : <Photo>[];

    // Handle location - can be string or object
    String parseLocation(dynamic location) {
      if (location == null) return 'Unknown';
      if (location is String) return location;
      if (location is Map) {
        final city = location['city'] ?? '';
        final state = location['state'] ?? '';
        if (city.isNotEmpty && state.isNotEmpty) {
          return '$city, $state';
        }
        return city.isNotEmpty ? city : 'Unknown';
      }
      return 'Unknown';
    }

    // Parse preferences
    final preferences = json['preferences'] as Map<String, dynamic>? ?? {};

    return User(
      id: json['id']?.toString() ?? '',
      email: json['email'],
      name: json['name'] ?? '',
      age: json['age'] ?? 18,
      bio: json['bio'] ?? '',
      photos: photos,
      location: parseLocation(json['location']),
      // Zero counts as unknown. A server that has not deployed the real
      // computation still sends 0, and a genuine 0 km means standing on the exact
      // same point — so reading it as unknown removes "0 km away" without waiting
      // for the deploy.
      distance: _parseDistance(json['distance']),
      interests: List<String>.from(json['interests'] ?? []),
      // Both spellings, like every neighbouring dual-convention field.
      // /users/me and /discover emit snake_case but authService.toPublic —
      // behind every /auth/* response — emits camelCase, so reading only
      // snake_case left the user empty-languaged right after login and chat
      // auto-translation defaulted off until a later /users/me refetch.
      languagesSpoken: List<String>.from(
          json['languages_spoken'] ?? json['languagesSpoken'] ?? []),
      languagesLearning: List<String>.from(
          json['languages_learning'] ?? json['languagesLearning'] ?? []),
      gender: _parseGender(json['gender']),
      lookingFor: _parseGender(json['looking_for'] ?? json['lookingFor']),
      minAgePreference: preferences['min_age'] ?? preferences['minAge'] ?? 18,
      maxAgePreference: preferences['max_age'] ?? preferences['maxAge'] ?? 50,
      maxDistancePreference:
          (preferences['max_distance'] ?? preferences['maxDistance'] ?? 50)
              .toDouble(),
      showDistance:
          preferences['show_distance'] ?? preferences['showDistance'] ?? true,
      interestsFilter: List<String>.from(
          preferences['interests_filter'] ?? preferences['interestsFilter'] ?? []),
      showOnlineStatus: preferences['show_online_status'] ??
          preferences['showOnlineStatus'] ??
          true,
      lastActive: (json['last_active'] ?? json['lastActive']) != null
          ? DateTime.parse(json['last_active'] ?? json['lastActive'])
          : DateTime.now(),
      isOnline: json['is_online'] ?? json['isOnline'] ?? false,
      isVerified: json['is_verified'] ?? json['isVerified'] ?? false,
      createdAt: (json['created_at'] ?? json['createdAt']) != null
          ? DateTime.parse(json['created_at'] ?? json['createdAt'])
          : null,
      commonInterests: json['common_interests'] != null
          ? List<String>.from(json['common_interests'])
          : null,
      // Accept both conventions, like every neighbouring field. These two
      // were the only pair here without a camelCase fallback, so an
      // entitlement delivered as `isPremium` parsed to false and a paying
      // user read as not premium — silently, since `?? false` cannot tell
      // "absent" from "not premium".
      isPremium: json['is_premium'] ?? json['isPremium'] ?? false,
      premiumExpiresAt:
          (json['premium_expires_at'] ?? json['premiumExpiresAt']) != null
              ? DateTime.parse(
                  json['premium_expires_at'] ?? json['premiumExpiresAt'])
              : null,
      superLikesRemaining: json['super_likes_remaining'] ?? 3,
      isProfileComplete: json['is_profile_complete'] as bool?,
      termsAcceptedAt:
          (json['termsAcceptedAt'] ?? json['terms_accepted_at']) != null
              ? DateTime.tryParse(
                  '${json['termsAcceptedAt'] ?? json['terms_accepted_at']}')
              : null,
      hasPassword:
          (json['has_password'] ?? json['hasPassword'] ?? true) as bool,
      locale: json['locale'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'age': age,
      'bio': bio,
      'photos': photos,
      'location': location,
      'interests': interests,
      'gender': _genderToString(gender),
      'looking_for': _genderToString(lookingFor),
      'preferences': {
        'min_age': minAgePreference,
        'max_age': maxAgePreference,
        'max_distance': maxDistancePreference,
        'interests_filter': interestsFilter,
        'show_distance': showDistance,
        'show_online_status': showOnlineStatus,
      },
      'is_online': isOnline,
      'is_verified': isVerified,
      'is_premium': isPremium,
      'premium_expires_at': premiumExpiresAt?.toIso8601String(),
      'super_likes_remaining': superLikesRemaining,
      'locale': locale,
    };
  }

  User copyWith({
    String? id,
    String? email,
    String? name,
    int? age,
    String? bio,
    List<Photo>? photos,
    String? location,
    double? distance,
    List<String>? interests,
    List<String>? languagesSpoken,
    List<String>? languagesLearning,
    Gender? gender,
    Gender? lookingFor,
    int? minAgePreference,
    int? maxAgePreference,
    double? maxDistancePreference,
    List<String>? interestsFilter,
    bool? showDistance,
    bool? showOnlineStatus,
    DateTime? lastActive,
    bool? isOnline,
    bool? isVerified,
    DateTime? createdAt,
    List<String>? commonInterests,
    bool? isPremium,
    DateTime? premiumExpiresAt,
    int? superLikesRemaining,
    bool? isProfileComplete,
    DateTime? termsAcceptedAt,
    bool? hasPassword,
    String? locale,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      age: age ?? this.age,
      bio: bio ?? this.bio,
      photos: photos ?? this.photos,
      location: location ?? this.location,
      distance: distance ?? this.distance,
      interests: interests ?? this.interests,
      languagesSpoken: languagesSpoken ?? this.languagesSpoken,
      languagesLearning: languagesLearning ?? this.languagesLearning,
      gender: gender ?? this.gender,
      lookingFor: lookingFor ?? this.lookingFor,
      minAgePreference: minAgePreference ?? this.minAgePreference,
      maxAgePreference: maxAgePreference ?? this.maxAgePreference,
      maxDistancePreference: maxDistancePreference ?? this.maxDistancePreference,
      interestsFilter: interestsFilter ?? this.interestsFilter,
      showDistance: showDistance ?? this.showDistance,
      showOnlineStatus: showOnlineStatus ?? this.showOnlineStatus,
      lastActive: lastActive ?? this.lastActive,
      isOnline: isOnline ?? this.isOnline,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
      commonInterests: commonInterests ?? this.commonInterests,
      isPremium: isPremium ?? this.isPremium,
      premiumExpiresAt: premiumExpiresAt ?? this.premiumExpiresAt,
      superLikesRemaining: superLikesRemaining ?? this.superLikesRemaining,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
      termsAcceptedAt: termsAcceptedAt ?? this.termsAcceptedAt,
      hasPassword: hasPassword ?? this.hasPassword,
      locale: locale ?? this.locale,
    );
  }

  /// The photo shown wherever one photo stands for the user.
  ///
  /// Null when they have none — callers must handle that rather than receive an
  /// empty string that fails later at the image layer.
  Photo? get primaryPhoto => photos.isEmpty ? null : photos.first;

  static Gender _parseGender(String? gender) {
    switch (gender?.toLowerCase()) {
      case 'male':
        return Gender.male;
      case 'female':
        return Gender.female;
      case 'non_binary':
      case 'nonbinary':
        return Gender.nonBinary;
      default:
        return Gender.other;
    }
  }

  static String _genderToString(Gender gender) {
    switch (gender) {
      case Gender.male:
        return 'male';
      case Gender.female:
        return 'female';
      case Gender.nonBinary:
        return 'non_binary';
      case Gender.other:
        return 'other';
    }
  }
}

enum Gender {
  male('Male'),
  female('Female'),
  nonBinary('Non-binary'),
  other('Other');

  final String displayName;
  const Gender(this.displayName);

  String toApiString() {
    switch (this) {
      case Gender.male:
        return 'male';
      case Gender.female:
        return 'female';
      case Gender.nonBinary:
        return 'non_binary';
      case Gender.other:
        return 'other';
    }
  }

  static Gender fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'male':
        return Gender.male;
      case 'female':
        return Gender.female;
      case 'non_binary':
      case 'nonbinary':
        return Gender.nonBinary;
      default:
        return Gender.other;
    }
  }
}
