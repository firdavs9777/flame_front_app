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
        minFaceSize: 0.15, // Minimum face size relative to image
      ),
    );
    _initialized = true;
  }

  /// Validates an image file contains a real face
  /// Returns a FaceValidationResult with details about the validation
  Future<FaceValidationResult> validateFace(File imageFile) async {
    _initializeDetector();

    try {
      final inputImage = InputImage.fromFile(imageFile);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) {
        return FaceValidationResult(
          isValid: false,
          error: 'No face detected in the photo. Please upload a clear photo of your face.',
          faceCount: 0,
        );
      }

      if (faces.length > 1) {
        return FaceValidationResult(
          isValid: false,
          error: 'Multiple faces detected. Please upload a photo with only your face.',
          faceCount: faces.length,
        );
      }

      final face = faces.first;

      // Check face size (should be reasonably large in the frame)
      final boundingBox = face.boundingBox;
      final faceArea = boundingBox.width * boundingBox.height;

      // Get image dimensions to calculate relative face size
      // For now, we'll use a minimum absolute size
      if (faceArea < 10000) { // Minimum 100x100 pixels roughly
        return FaceValidationResult(
          isValid: false,
          error: 'Face is too small. Please upload a closer photo of your face.',
          faceCount: 1,
        );
      }

      // Check head rotation (face should be mostly frontal)
      final headEulerAngleY = face.headEulerAngleY; // Left/right rotation
      final headEulerAngleZ = face.headEulerAngleZ; // Tilt

      if (headEulerAngleY != null && headEulerAngleY.abs() > 35) {
        return FaceValidationResult(
          isValid: false,
          error: 'Please face the camera more directly.',
          faceCount: 1,
        );
      }

      if (headEulerAngleZ != null && headEulerAngleZ.abs() > 25) {
        return FaceValidationResult(
          isValid: false,
          error: 'Please keep your head straight (not tilted).',
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
