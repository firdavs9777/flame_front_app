import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:flame/theme/app_theme.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/location_service.dart';
import 'package:flame/services/user_service.dart';
import 'photo_uploader.dart';
import 'registration_draft.dart';
import 'steps/step_email_password.dart';
import 'steps/step_profile_info.dart';
import 'steps/step_looking_for.dart';
import 'steps/step_bio_interests.dart';
import 'steps/step_photos.dart';

class RegistrationData {
  String email = '';
  String password = '';
  String name = '';
  int age = 18;
  Gender gender = Gender.other;
  Gender lookingFor = Gender.other;
  String bio = '';
  List<String> interests = [];
  List<String> photos = []; // URLs after upload
  List<File> photoFiles = []; // Local files before upload
  double? latitude;
  double? longitude;
}

class RegistrationFlow extends ConsumerStatefulWidget {
  const RegistrationFlow({super.key});

  @override
  ConsumerState<RegistrationFlow> createState() => _RegistrationFlowState();
}

class _RegistrationFlowState extends ConsumerState<RegistrationFlow> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 5; // 5-step flow; no email verification
  final RegistrationData _data = RegistrationData();
  final RegistrationDraft _draft = const RegistrationDraft();
  bool _isUploading = false;
  bool _registrationComplete = false;

  final List<String> _stepTitles = [
    'Create Account',
    'About You',
    'Looking For',
    'Your Interests',
    'Add Photos',
  ];

  final List<String> _stepSubtitles = [
    'Enter your email and create a password',
    'Tell us a bit about yourself',
    'Who would you like to meet?',
    'What makes you, you?',
    'Show off your best self',
  ];

  @override
  void initState() {
    super.initState();
    // Offer to resume a previously-saved draft, if any.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferResume());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _maybeOfferResume() async {
    final saved = await _draft.load();
    if (saved == null || !mounted) return;
    // Nothing meaningful to resume (fresh/empty draft) — skip the prompt.
    if (saved.step <= 0 && saved.data.email.isEmpty) {
      await _draft.clear();
      return;
    }

    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Resume your signup?'),
        content: const Text(
          'We saved your progress. Pick up where you left off, or start over.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Start Over'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resume'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (resume == true) {
      _restoreFrom(saved.data, saved.step);
    } else {
      await _draft.clear();
    }
  }

  void _restoreFrom(RegistrationData data, int step) {
    _data
      ..email = data.email
      ..name = data.name
      ..age = data.age
      ..gender = data.gender
      ..lookingFor = data.lookingFor
      ..bio = data.bio
      ..interests = data.interests
      ..photoFiles = data.photoFiles
      ..latitude = data.latitude
      ..longitude = data.longitude;

    final target = step.clamp(0, _totalSteps - 1);
    setState(() => _currentStep = target);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(target);
    }
  }

  void _saveDraft() {
    // Fire-and-forget; a persistence hiccup must never block the UI.
    _draft.save(_data, _currentStep);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.isAuthenticated && _registrationComplete) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        ref.read(authProvider.notifier).clearError();
      }
    });

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFF6B6B),
              Color(0xFFFF8E53),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header with back button and progress
              _buildHeader()
                  .animate()
                  .fadeIn(duration: 400.ms),

              const SizedBox(height: 16),

              // Progress indicator
              _buildProgressIndicator()
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 400.ms),

              const SizedBox(height: 24),

              // Step title and subtitle
              _buildStepInfo()
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 400.ms)
                  .slideX(begin: -0.1, end: 0, delay: 200.ms, duration: 400.ms),

              const SizedBox(height: 24),

              // Page content
              Expanded(
                child: _buildPageView(authState),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: _handleBack,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          Text(
            'Step ${_currentStep + 1} of $_totalSteps',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 48), // Balance the back button
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: List.generate(_totalSteps, (index) {
          final isCompleted = index < _currentStep;
          final isCurrent = index == _currentStep;

          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: index < _totalSteps - 1 ? 8 : 0),
              decoration: BoxDecoration(
                color: isCompleted || isCurrent
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepInfo() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _stepTitles[_currentStep],
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _stepSubtitles[_currentStep],
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageView(AuthState authState) {
    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      onPageChanged: (index) {
        setState(() => _currentStep = index);
        _saveDraft();
      },
      children: [
        StepEmailPassword(
          data: _data,
          onNext: _goToNextStep,
        ),
        StepProfileInfo(
          data: _data,
          onNext: _goToNextStep,
        ),
        StepLookingFor(
          data: _data,
          onNext: _goToNextStep,
        ),
        StepBioInterests(
          data: _data,
          onNext: _goToNextStep,
        ),
        StepPhotos(
          data: _data,
          isLoading: authState.isLoading || _isUploading,
          onComplete: _handlePhotosComplete,
        ),
      ],
    );
  }

  void _handleBack() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      // Explicit back-out to login/welcome — discard the saved draft.
      _draft.clear();
      Navigator.of(context).pop();
    }
  }

  void _goToNextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _handlePhotosComplete() async {
    setState(() => _isUploading = true);

    try {
      // Request location permission and get current location
      final locationService = LocationService();
      final locationResult = await locationService.getCurrentPosition();

      if (!locationResult.success) {
        setState(() => _isUploading = false);
        if (mounted) {
          _showLocationError(locationResult.error ?? 'Failed to get location');
        }
        return;
      }

      _data.latitude = locationResult.latitude;
      _data.longitude = locationResult.longitude;

      // Upload photos FIRST and get URLs back
      final photoUrls = await _uploadPhotosForRegistration();

      if (photoUrls.isEmpty) {
        setState(() => _isUploading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Failed to upload photos. Please try again.'),
              backgroundColor: AppTheme.errorColor,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }

      // Register user with photo URLs
      final success = await ref.read(authProvider.notifier).register(
            email: _data.email,
            password: _data.password,
            name: _data.name,
            age: _data.age,
            gender: _data.gender,
            lookingFor: _data.lookingFor,
            bio: _data.bio,
            interests: _data.interests,
            photos: photoUrls,
            latitude: _data.latitude!,
            longitude: _data.longitude!,
          );

      setState(() => _isUploading = false);

      if (success) {
        // Registration is complete — tokens are already issued. The ref.listen
        // above pops to root once auth state flips to authenticated. Drop the
        // saved draft so a future signup starts clean.
        await _draft.clear();
        setState(() => _registrationComplete = true);
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<List<String>> _uploadPhotosForRegistration() async {
    if (_data.photoFiles.isEmpty) return [];

    final userService = UserService();

    String tempPath;
    try {
      tempPath = (await getTemporaryDirectory()).path;
    } catch (_) {
      // path_provider unavailable on some simulators; fall back to system temp
      tempPath = Directory.systemTemp.path;
    }

    // Index each file so compression temp paths and debug logs stay stable
    // even though uploads run concurrently.
    final indexOf = <File, int>{};
    for (var i = 0; i < _data.photoFiles.length; i++) {
      indexOf[_data.photoFiles[i]] = i;
    }

    final photoUrls = await const PhotoUploader().upload(
      _data.photoFiles,
      uploadOne: (file, {required bool isPrimary}) async {
        final i = indexOf[file] ?? 0;
        try {
          // Compress + convert to JPEG before upload.
          final compressedFile = await _compressImage(file, tempPath, i);

          final result = await userService.uploadPhotoForRegistration(
            compressedFile,
            isPrimary: isPrimary,
          );

          if (result.success && result.data != null) {
            debugPrint('Uploaded photo ${i + 1}: ${result.data!.url}');
            return UploadOutcome(success: true, url: result.data!.url);
          }
          debugPrint('Failed to upload photo ${i + 1}: ${result.error}');
          return const UploadOutcome(success: false);
        } catch (e) {
          debugPrint('Error uploading photo ${i + 1}: $e');
          return const UploadOutcome(success: false);
        }
      },
    );

    return photoUrls;
  }

  Future<File> _compressImage(File file, String tempPath, int index) async {
    try {
      final bytes = await file.readAsBytes();
      final originalSize = bytes.length;
      debugPrint('Original photo ${index + 1} size: ${(originalSize / 1024).toStringAsFixed(0)} KB');

      // Decode image
      img.Image? image = img.decodeImage(bytes);
      if (image == null) {
        debugPrint('Could not decode image, using original');
        return file;
      }

      // Resize if larger than 800px
      const maxSize = 800;
      if (image.width > maxSize || image.height > maxSize) {
        if (image.width > image.height) {
          image = img.copyResize(image, width: maxSize);
        } else {
          image = img.copyResize(image, height: maxSize);
        }
      }

      // Encode as JPEG with 70% quality
      final compressedBytes = img.encodeJpg(image, quality: 70);
      debugPrint('Compressed photo ${index + 1} size: ${(compressedBytes.length / 1024).toStringAsFixed(0)} KB');

      // Save to temp file
      final compressedPath = '$tempPath/compressed_$index.jpg';
      final compressedFile = File(compressedPath);
      await compressedFile.writeAsBytes(compressedBytes);

      return compressedFile;
    } catch (e) {
      debugPrint('Compression error: $e, using original');
      return file;
    }
  }

  void _showLocationError(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Required'),
        content: Text(
          '$error\n\nFlame needs your location to find matches near you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final locationService = LocationService();
              await locationService.openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}
