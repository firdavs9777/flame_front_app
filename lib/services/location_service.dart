import 'package:geolocator/geolocator.dart';

class LocationService {
  // Singleton
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Position? _lastPosition;
  Position? get lastPosition => _lastPosition;

  /// Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Check current permission status
  Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  /// Request location permission
  Future<LocationPermission> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission;
  }

  /// Check if we have usable permission
  bool hasPermission(LocationPermission permission) {
    return permission == LocationPermission.always ||
           permission == LocationPermission.whileInUse;
  }

  /// Get current position
  Future<LocationResult> getCurrentPosition() async {
    try {
      // Check if location service is enabled
      final serviceEnabled = await isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationResult.failure(
          'Location services are disabled. Please enable them in settings.',
          reason: LocationFailure.serviceDisabled,
        );
      }

      // Check permission
      LocationPermission permission = await checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await requestPermission();
        if (permission == LocationPermission.denied) {
          return LocationResult.failure(
            'Location permission denied. Please allow location access to continue.',
            reason: LocationFailure.permissionDenied,
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return LocationResult.failure(
          'Location permission permanently denied. Please enable it in app settings.',
          reason: LocationFailure.permissionDeniedForever,
        );
      }

      // Get position
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      _lastPosition = position;
      return LocationResult.success(position);
    } catch (e) {
      // Everything that lands here has permission and simply did not produce
      // a fix: the 15s timeLimit above expiring indoors is the common one.
      return LocationResult.failure(
        'Failed to get location: ${e.toString()}',
        reason: LocationFailure.positionUnavailable,
      );
    }
  }

  /// Open app settings (for when permission is permanently denied)
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Open location settings (for when service is disabled)
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }
}

/// Why a location lookup failed.
///
/// The distinction that matters is refusal versus not-this-time. A person who
/// denied permission should not be asked again every few minutes; a person
/// standing indoors whose GPS did not fix within the time limit has refused
/// nothing, and telling them it is a permission problem is simply wrong.
enum LocationFailure {
  /// Device location services are switched off. Not a refusal aimed at this
  /// app, and it costs nothing to look again — it returns immediately.
  serviceDisabled,

  /// The person was asked and said no.
  permissionDenied,

  /// Denied permanently; only Settings can change it.
  permissionDeniedForever,

  /// Permission is fine and no fix arrived — a timeout indoors, a cold start,
  /// a platform error. Transient by nature.
  positionUnavailable,
}

class LocationResult {
  final bool success;
  final Position? position;
  final String? error;

  /// Null only for a success, or a failure built by older code that predates
  /// the distinction.
  final LocationFailure? reason;

  /// Set only by [LocationResult.successAt], for callers that have coordinates
  /// but no Position.
  final double? _latitude;
  final double? _longitude;

  LocationResult._({
    required this.success,
    this.position,
    this.error,
    this.reason,
    double? latitude,
    double? longitude,
  })  : _latitude = latitude,
        _longitude = longitude;

  factory LocationResult.success(Position position) {
    return LocationResult._(success: true, position: position);
  }

  /// Coordinates without a Position.
  ///
  /// A Position cannot be constructed in a unit test without a platform channel,
  /// so a fake location source has no way to report success through
  /// [LocationResult.success]. Callers that only need the pair use this.
  factory LocationResult.successAt(double latitude, double longitude) {
    return LocationResult._(
      success: true,
      latitude: latitude,
      longitude: longitude,
    );
  }

  factory LocationResult.failure(String error, {LocationFailure? reason}) {
    return LocationResult._(success: false, error: error, reason: reason);
  }

  /// Whether the person (or the OS on their behalf) refused this app.
  ///
  /// Only this justifies giving up for the session. Everything else is worth
  /// another attempt, because it may simply work next time.
  bool get isRefusal =>
      reason == LocationFailure.permissionDenied ||
      reason == LocationFailure.permissionDeniedForever;

  double? get latitude => position?.latitude ?? _latitude;
  double? get longitude => position?.longitude ?? _longitude;
}
