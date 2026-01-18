class User {
  final String id;
  final String? email;
  final String name;
  final int age;
  final String bio;
  final List<String> photos;
  final String location;
  final double distance;
  final List<String> interests;
  final Gender gender;
  final Gender lookingFor;
  final int minAgePreference;
  final int maxAgePreference;
  final double maxDistancePreference;
  final bool showDistance;
  final bool showOnlineStatus;
  final DateTime lastActive;
  final bool isOnline;
  final bool isVerified;
  final DateTime? createdAt;
  final List<String>? commonInterests;
  final bool isPremium;
  final DateTime? premiumExpiresAt;
  final int superLikesRemaining;

  const User({
    required this.id,
    this.email,
    required this.name,
    required this.age,
    required this.bio,
    required this.photos,
    required this.location,
    this.distance = 0,
    required this.interests,
    required this.gender,
    required this.lookingFor,
    this.minAgePreference = 18,
    this.maxAgePreference = 50,
    this.maxDistancePreference = 50,
    this.showDistance = true,
    this.showOnlineStatus = true,
    required this.lastActive,
    this.isOnline = false,
    this.isVerified = false,
    this.createdAt,
    this.commonInterests,
    this.isPremium = false,
    this.premiumExpiresAt,
    this.superLikesRemaining = 3,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // Handle photos - can be list of strings or list of objects
    List<String> parsePhotos(dynamic photos) {
      if (photos == null) return [];
      if (photos is List) {
        return photos.map((p) {
          if (p is String) return p;
          if (p is Map) return p['url']?.toString() ?? '';
          return '';
        }).where((p) => p.isNotEmpty).toList();
      }
      return [];
    }

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
      photos: parsePhotos(json['photos']),
      location: parseLocation(json['location']),
      distance: (json['distance'] ?? 0).toDouble(),
      interests: List<String>.from(json['interests'] ?? []),
      gender: _parseGender(json['gender']),
      lookingFor: _parseGender(json['looking_for']),
      minAgePreference: preferences['min_age'] ?? 18,
      maxAgePreference: preferences['max_age'] ?? 50,
      maxDistancePreference: (preferences['max_distance'] ?? 50).toDouble(),
      showDistance: preferences['show_distance'] ?? true,
      showOnlineStatus: preferences['show_online_status'] ?? true,
      lastActive: json['last_active'] != null
          ? DateTime.parse(json['last_active'])
          : DateTime.now(),
      isOnline: json['is_online'] ?? false,
      isVerified: json['is_verified'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      commonInterests: json['common_interests'] != null
          ? List<String>.from(json['common_interests'])
          : null,
      isPremium: json['is_premium'] ?? false,
      premiumExpiresAt: json['premium_expires_at'] != null
          ? DateTime.parse(json['premium_expires_at'])
          : null,
      superLikesRemaining: json['super_likes_remaining'] ?? 3,
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
        'show_distance': showDistance,
        'show_online_status': showOnlineStatus,
      },
      'is_online': isOnline,
      'is_verified': isVerified,
      'is_premium': isPremium,
      'premium_expires_at': premiumExpiresAt?.toIso8601String(),
      'super_likes_remaining': superLikesRemaining,
    };
  }

  User copyWith({
    String? id,
    String? email,
    String? name,
    int? age,
    String? bio,
    List<String>? photos,
    String? location,
    double? distance,
    List<String>? interests,
    Gender? gender,
    Gender? lookingFor,
    int? minAgePreference,
    int? maxAgePreference,
    double? maxDistancePreference,
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
      gender: gender ?? this.gender,
      lookingFor: lookingFor ?? this.lookingFor,
      minAgePreference: minAgePreference ?? this.minAgePreference,
      maxAgePreference: maxAgePreference ?? this.maxAgePreference,
      maxDistancePreference: maxDistancePreference ?? this.maxDistancePreference,
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
    );
  }

  String get primaryPhoto => photos.isNotEmpty ? photos.first : '';

  String get distanceText => '${distance.toStringAsFixed(0)} km away';

  String get lastActiveText {
    final now = DateTime.now();
    final diff = now.difference(lastActive);

    if (isOnline) return 'Online now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return 'Long time ago';
  }

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
