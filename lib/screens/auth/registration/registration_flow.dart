import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../models/user.dart';
import '../../../services/user_service.dart';
import 'steps/step_email_password.dart';
import 'steps/step_profile_info.dart';
import 'steps/step_looking_for.dart';
import 'steps/step_bio_interests.dart';
import 'steps/step_photos.dart';
import 'steps/step_verify_email.dart';

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
}

class RegistrationFlow extends ConsumerStatefulWidget {
  const RegistrationFlow({super.key});

  @override
  ConsumerState<RegistrationFlow> createState() => _RegistrationFlowState();
}

class _RegistrationFlowState extends ConsumerState<RegistrationFlow> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 6; // Added verify email step
  final RegistrationData _data = RegistrationData();
  bool _isUploading = false;
  bool _registrationComplete = false;

  final List<String> _stepTitles = [
    'Create Account',
    'About You',
    'Looking For',
    'Your Interests',
    'Add Photos',
    'Verify Email',
  ];

  final List<String> _stepSubtitles = [
    'Enter your email and create a password',
    'Tell us a bit about yourself',
    'Who would you like to meet?',
    'What makes you, you?',
    'Show off your best self',
    'Enter the code we sent you',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
      onPageChanged: (index) => setState(() => _currentStep = index),
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
        StepVerifyEmail(
          email: _data.email,
          onVerified: _handleEmailVerified,
          onResend: _handleResendCode,
        ),
      ],
    );
  }

  void _handleBack() {
    if (_currentStep > 0) {
      // Don't allow going back from verify email step
      if (_currentStep == 5) {
        _showCancelDialog();
        return;
      }
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _showCancelDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Registration?'),
        content: const Text(
          'You need to verify your email to complete registration. Are you sure you want to cancel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue Verification'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
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
      // Upload photos first
      final userService = UserService();
      final uploadedUrls = <String>[];

      for (int i = 0; i < _data.photoFiles.length; i++) {
        final file = _data.photoFiles[i];
        final result = await userService.uploadPhotoForRegistration(
          file,
          isPrimary: i == 0,
        );

        if (result.success && result.data != null) {
          uploadedUrls.add(result.data!.url);
        } else {
          throw Exception(result.error ?? 'Failed to upload photo ${i + 1}');
        }
      }

      _data.photos = uploadedUrls;

      // Register user
      final success = await ref.read(authProvider.notifier).register(
            email: _data.email,
            password: _data.password,
            name: _data.name,
            age: _data.age,
            gender: _data.gender,
            lookingFor: _data.lookingFor,
            bio: _data.bio,
            interests: _data.interests,
            photos: _data.photos,
          );

      setState(() => _isUploading = false);

      if (success) {
        // Go to email verification step
        _goToNextStep();
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

  void _handleEmailVerified() {
    setState(() => _registrationComplete = true);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _handleResendCode() async {
    // Resend verification code logic is handled in the verify email step
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Verification code resent!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
