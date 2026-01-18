import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/services/face_detection_service.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';

class StepPhotos extends StatefulWidget {
  final RegistrationData data;
  final bool isLoading;
  final VoidCallback onComplete;

  const StepPhotos({
    super.key,
    required this.data,
    required this.isLoading,
    required this.onComplete,
  });

  @override
  State<StepPhotos> createState() => _StepPhotosState();
}

class _StepPhotosState extends State<StepPhotos> {
  final List<PhotoData?> _photos = List.filled(6, null);
  final ImagePicker _imagePicker = ImagePicker();
  final FaceDetectionService _faceDetection = FaceDetectionService();
  bool _isProcessing = false;
  int? _processingIndex;

  @override
  void initState() {
    super.initState();
    // Restore any previously selected photos
    for (int i = 0; i < widget.data.photoFiles.length && i < 6; i++) {
      _photos[i] = PhotoData(file: widget.data.photoFiles[i]);
    }
  }

  int get _photoCount => _photos.where((p) => p != null).length;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Add Your Photos',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _photoCount >= 2
                        ? AppTheme.successColor.withValues(alpha: 0.1)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_photoCount/6',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _photoCount >= 2
                          ? AppTheme.successColor
                          : Colors.grey[500],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Add at least 2 photos with your face clearly visible. Your first photo will be your main profile picture.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            // Photo Grid
            _buildPhotoGrid()
                .animate()
                .fadeIn(delay: 100.ms, duration: 400.ms),

            const SizedBox(height: 16),

            // Face Detection Info
            _buildFaceDetectionInfo()
                .animate()
                .fadeIn(delay: 150.ms, duration: 400.ms),

            const SizedBox(height: 16),

            // Tips
            _buildTips()
                .animate()
                .fadeIn(delay: 200.ms, duration: 400.ms),

            const SizedBox(height: 32),

            // Complete Button
            _buildCompleteButton()
                .animate()
                .fadeIn(delay: 300.ms, duration: 400.ms)
                .slideY(begin: 0.2, end: 0, delay: 300.ms, duration: 400.ms),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0, duration: 400.ms),
    );
  }

  Widget _buildFaceDetectionInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.face_retouching_natural, color: Colors.green[700], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'We verify photos contain a real face for safety',
              style: TextStyle(
                fontSize: 13,
                color: Colors.green[800],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: 6,
      itemBuilder: (context, index) => _buildPhotoSlot(index),
    );
  }

  Widget _buildPhotoSlot(int index) {
    final photo = _photos[index];
    final isMain = index == 0;
    final isProcessingThis = _isProcessing && _processingIndex == index;

    return GestureDetector(
      onTap: isProcessingThis ? null : () => _handlePhotoTap(index),
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: photo != null
                    ? Colors.transparent
                    : (isMain ? AppTheme.primaryColor : Colors.grey[300]!),
                width: isMain && photo == null ? 2 : 1,
                style: photo == null ? BorderStyle.solid : BorderStyle.none,
              ),
              image: photo?.file != null
                  ? DecorationImage(
                      image: FileImage(photo!.file!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: photo == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isMain
                                ? AppTheme.primaryColor
                                : Colors.grey[300],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.add_rounded,
                            color: isMain ? Colors.white : Colors.grey[600],
                            size: 24,
                          ),
                        ),
                        if (isMain) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Main',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : null,
          ),
          // Processing overlay
          if (isProcessingThis)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Verifying...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Remove button
          if (photo != null && !isProcessingThis)
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () => _removePhoto(index),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          // Main badge
          if (photo != null && isMain)
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Main',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          // Face verified badge
          if (photo != null && photo.faceVerified)
            Positioned(
              top: 6,
              left: 6,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTips() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            color: Colors.blue[700],
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Profiles with multiple photos get more matches! Show your hobbies and personality.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.blue[800],
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: (widget.isLoading || _isProcessing) ? null : _handleComplete,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          disabledBackgroundColor: AppTheme.primaryColor.withValues(alpha: 0.6),
        ),
        child: widget.isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Complete Profile',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.check_circle_outline_rounded, size: 22),
                ],
              ),
      ),
    );
  }

  void _handlePhotoTap(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Add Photo',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppTheme.primaryColor,
                ),
              ),
              title: const Text('Take Photo'),
              subtitle: const Text('Use your camera'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _pickImage(index, ImageSource.camera);
              },
            ),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  color: Colors.purple,
                ),
              ),
              title: const Text('Choose from Gallery'),
              subtitle: const Text('Select existing photo'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(context);
                _pickImage(index, ImageSource.gallery);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(int index, ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      setState(() {
        _isProcessing = true;
        _processingIndex = index;
      });

      final file = File(pickedFile.path);

      // Validate face in the image (strict mode for main photo only)
      final isMainPhoto = index == 0;
      final result = await _faceDetection.validateFace(file, strictMode: isMainPhoto);

      if (!result.isValid) {
        setState(() {
          _isProcessing = false;
          _processingIndex = null;
        });

        if (mounted) {
          _showError(result.error ?? 'Photo validation failed');
        }
        return;
      }

      // Face detected successfully
      setState(() {
        _photos[index] = PhotoData(
          file: file,
          faceVerified: true,
        );
        _isProcessing = false;
        _processingIndex = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Face verified successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _processingIndex = null;
      });

      if (mounted) {
        _showError('Failed to process image: ${e.toString()}');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppTheme.errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _removePhoto(int index) {
    setState(() {
      _photos[index] = null;
    });
  }

  void _handleComplete() {
    if (_photoCount < 2) {
      _showError('Please add at least 2 photos');
      return;
    }

    // Check if at least the main photo has face verification
    final mainPhoto = _photos[0];
    if (mainPhoto == null || !mainPhoto.faceVerified) {
      _showError('Your main photo must have a verified face');
      return;
    }

    // Save photo files to registration data
    widget.data.photoFiles = _photos
        .where((p) => p != null && p.file != null)
        .map((p) => p!.file!)
        .toList();

    widget.onComplete();
  }
}

class PhotoData {
  final File? file;
  final String? url;
  final bool faceVerified;

  PhotoData({
    this.file,
    this.url,
    this.faceVerified = false,
  });
}
