import 'dart:io';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectionService {
  static final FaceDetectionService _instance = FaceDetectionService._internal();
  factory FaceDetectionService() => _instance;
  FaceDetectionService._internal();

  late final FaceDetector _faceDetector;
  bool _initialized = false;

  void _initializeDetector() {
    if (_initialized) return;

    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // For smile/eyes open detection
        enableLandmarks: true,
        enableContours: false,
        enableTracking: false,
        performanceMode: FaceDetectorMode.accurate,
        minFaceSize: 0.05, // Relaxed: detect smaller faces
      ),
    );
    _initialized = true;
  }

  /// Validates an image file contains a real face
  /// Returns a FaceValidationResult with details about the validation
  /// Set strictMode to true for main profile photo (single face required)
  Future<FaceValidationResult> validateFace(File imageFile, {bool strictMode = false}) async {
    _initializeDetector();

    try {
      final inputImage = InputImage.fromFile(imageFile);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return FaceValidationResult(
          isValid: false,
          error: 'No face detected. Please upload a photo with your face visible.',
          faceCount: 0,
        );
      }

      // Only enforce single face in strict mode (main profile photo)
      if (strictMode && faces.length > 1) {
        return FaceValidationResult(
          isValid: false,
          error: 'Multiple faces detected. Your main photo should show only you.',
          faceCount: faces.length,
        );
      }

      final face = faces.first;

      // Check face size (relaxed - allow smaller faces)
      final boundingBox = face.boundingBox;
      final faceArea = boundingBox.width * boundingBox.height;

      // Very lenient minimum size - just needs to be detectable
      if (faceArea < 2500) { // Minimum ~50x50 pixels
        return FaceValidationResult(
          isValid: false,
          error: 'Face is too small. Please upload a photo where your face is more visible.',
          faceCount: 1,
        );
      }

      // Check head rotation (relaxed - allow more angles)
      final headEulerAngleY = face.headEulerAngleY; // Left/right rotation
      final headEulerAngleZ = face.headEulerAngleZ; // Tilt

      // Only reject extreme angles (profile shots)
      if (headEulerAngleY != null && headEulerAngleY.abs() > 55) {
        return FaceValidationResult(
          isValid: false,
          error: 'Please upload a photo where your face is more visible.',
          faceCount: 1,
        );
      }

      // Very relaxed tilt check
      if (headEulerAngleZ != null && headEulerAngleZ.abs() > 45) {
        return FaceValidationResult(
          isValid: false,
          error: 'Please upload a photo where your face is more visible.',
          faceCount: 1,
        );
      }

      // All checks passed
      return FaceValidationResult(
        isValid: true,
        faceCount: 1,
        smilingProbability: face.smilingProbability,
        leftEyeOpenProbability: face.leftEyeOpenProbability,
        rightEyeOpenProbability: face.rightEyeOpenProbability,
      );
    } catch (e) {
      return FaceValidationResult(
        isValid: false,
        error: 'Failed to analyze photo: ${e.toString()}',
        faceCount: 0,
      );
    }
  }

  /// Quick check if image contains at least one face
  Future<bool> containsFace(File imageFile) async {
    final result = await validateFace(imageFile);
    return result.isValid;
  }

  void dispose() {
    if (_initialized) {
      _faceDetector.close();
      _initialized = false;
    }
  }
}

class FaceValidationResult {
  final bool isValid;
  final String? error;
  final int faceCount;
  final double? smilingProbability;
  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;

  FaceValidationResult({
    required this.isValid,
    this.error,
    required this.faceCount,
    this.smilingProbability,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
  });

  @override
  String toString() {
    return 'FaceValidationResult(isValid: $isValid, error: $error, faceCount: $faceCount)';
  }
}
