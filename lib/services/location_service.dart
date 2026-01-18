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
        return LocationResult.failure('Location services are disabled. Please enable them in settings.');
      }

      // Check permission
      LocationPermission permission = await checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await requestPermission();
        if (permission == LocationPermission.denied) {
          return LocationResult.failure('Location permission denied. Please allow location access to continue.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return LocationResult.failure('Location permission permanently denied. Please enable it in app settings.');
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
      return LocationResult.failure('Failed to get location: ${e.toString()}');
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

class LocationResult {
  final bool success;
  final Position? position;
  final String? error;

  LocationResult._({
    required this.success,
    this.position,
    this.error,
  });

  factory LocationResult.success(Position position) {
    return LocationResult._(success: true, position: position);
  }

  factory LocationResult.failure(String error) {
    return LocationResult._(success: false, error: error);
  }

  double? get latitude => position?.latitude;
  double? get longitude => position?.longitude;
}
