import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/services/auth_availability_service.dart';

/// Provides the email/identifier availability service. Overridable in tests.
final authAvailabilityServiceProvider = Provider<AuthAvailabilityService>(
  (ref) => AuthAvailabilityService(),
);
