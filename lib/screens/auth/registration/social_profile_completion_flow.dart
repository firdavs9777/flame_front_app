import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flame/core/image/photo_compressor.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/screens/auth/widgets/auth_snackbar.dart';
import 'steps/step_profile_info.dart';
import 'steps/step_looking_for.dart';
import 'steps/step_bio_interests.dart';
import 'steps/step_photos.dart';
import 'registration_flow.dart';

class SocialProfileCompletionFlow extends ConsumerStatefulWidget {
  const SocialProfileCompletionFlow({super.key});

  @override
  ConsumerState<SocialProfileCompletionFlow> createState() =>
      _SocialProfileCompletionFlowState();
}

class _SocialProfileCompletionFlowState
    extends ConsumerState<SocialProfileCompletionFlow> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final int _totalSteps = 4;
  final RegistrationData _data = RegistrationData();
  bool _isUploading = false;

  final List<String> _stepTitles = [
    'About You',
    'Looking For',
    'Your Interests',
    'Add Photos',
  ];

  final List<String> _stepSubtitles = [
    'Tell us a bit about yourself',
    'Who would you like to meet?',
    'What makes you, you?',
    'Show off your best self',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Pre-fill name from the authenticated social user
    if (_data.name.isEmpty && authState.user != null) {
      _data.name = authState.user!.name;
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader().animate().fadeIn(duration: 400.ms),
              const SizedBox(height: 16),
              _buildProgressIndicator()
                  .animate()
                  .fadeIn(delay: 100.ms, duration: 400.ms),
              const SizedBox(height: 24),
              _buildStepInfo()
                  .animate()
                  .fadeIn(delay: 200.ms, duration: 400.ms),
              const SizedBox(height: 24),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _currentStep = i),
                  children: [
                    StepProfileInfo(data: _data, onNext: _goToNextStep),
                    StepLookingFor(data: _data, onNext: _goToNextStep),
                    StepBioInterests(data: _data, onNext: _goToNextStep),
                    StepPhotos(
                      data: _data,
                      isLoading: _isUploading,
                      onComplete: _handleComplete,
                    ),
                  ],
                ),
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
          if (_currentStep > 0)
            IconButton(
              onPressed: () => _pageController.previousPage(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
              ),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 20),
              ),
            )
          else
            const SizedBox(width: 48),
          Text(
            'Step ${_currentStep + 1} of $_totalSteps',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: List.generate(_totalSteps, (index) {
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: index < _totalSteps - 1 ? 8 : 0),
              decoration: BoxDecoration(
                color: index <= _currentStep
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

  void _goToNextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _handleComplete() async {
    setState(() => _isUploading = true);

    try {
      final userService = UserService();

      final profileResult = await userService.updateProfile(
        name: _data.name,
        bio: _data.bio,
        interests: _data.interests,
        lookingFor: _data.lookingFor,
        gender: _data.gender,
        age: _data.age,
      );
      if (!mounted) return;

      if (!profileResult.success) {
        setState(() => _isUploading = false);
        showAuthSnackBar(
          context,
          message: profileResult.error ?? 'Failed to update profile',
          type: AuthSnackBarType.error,
        );
        return;
      }

      String tempPath;
      try {
        final dir = await Directory.systemTemp.createTemp('flame_photos');
        tempPath = dir.path;
      } catch (_) {
        tempPath = Directory.systemTemp.path;
      }

      for (int i = 0; i < _data.photoFiles.length; i++) {
        final file = _data.photoFiles[i];
        final isPrimary = i == 0;
        try {
          final compressed = await const PhotoCompressor()
              .compress(file, tempDir: tempPath, index: i);
          await userService.uploadPhoto(compressed, isPrimary: isPrimary);
        } catch (e) {
          debugPrint('Photo upload error: $e');
        }
      }
      if (!mounted) return;

      final userResult = await userService.getCurrentUser();
      if (!mounted) return;
      if (userResult.success && userResult.data != null) {
        ref.read(authProvider.notifier).updateUser(userResult.data!);
      }
      setState(() => _isUploading = false);
      ref.read(authProvider.notifier).markAuthenticated();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      showAuthSnackBar(
        context,
        message: 'Error: ${e.toString()}',
        type: AuthSnackBarType.error,
      );
    }
  }
}
