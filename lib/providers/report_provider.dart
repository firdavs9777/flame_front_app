import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/services/report_service.dart';

/// Provides the report/block service. Overridable in tests.
final reportServiceProvider = Provider<ReportService>((ref) => ReportService());
