import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flame/core/image/photo_compressor.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/location_service.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/screens/auth/widgets/auth_snackbar.dart';
import 'photo_uploader.dart';
import 'registration_draft.dart';
import 'step_wizard.dart';
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
  final GlobalKey<StepWizardState> _wizardKey = GlobalKey<StepWizardState>();
  final RegistrationData _data = RegistrationData();
  final RegistrationDraft _draft = const RegistrationDraft();
  bool _isUploading = false;
  bool _registrationComplete = false;

  static const int _totalSteps = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferResume());
  }

  Future<void> _maybeOfferResume() async {
    final saved = await _draft.load();
    if (saved == null || !mounted) return;
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

    _wizardKey.currentState?.jumpToStep(
      resumeStepFor(
        password: _data.password,
        savedStep: step,
        totalSteps: _totalSteps,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (_registrationComplete &&
          (next.isAuthenticated || next.isProfileIncomplete)) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      if (next.error != null) {
        showAuthSnackBar(
          context,
          message: next.error!,
          type: AuthSnackBarType.error,
        );
        ref.read(authProvider.notifier).clearError();
      }
    });

    final busy = authState.isLoading || _isUploading;

    return StepWizard(
      key: _wizardKey,
      isBusy: busy,
      onStepChanged: (step) => _draft.save(_data, step),
      onExit: () {
        // Explicit back-out to welcome — discard the saved draft.
        _draft.clear();
        Navigator.of(context).pop();
      },
      onComplete: _registerNewAccount,
      steps: [
        WizardStep(
          title: 'Create Account',
          subtitle: 'Enter your email and create a password',
          builder: (context, onNext) =>
              StepEmailPassword(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: 'About You',
          subtitle: 'Tell us a bit about yourself',
          builder: (context, onNext) =>
              StepProfileInfo(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: 'Looking For',
          subtitle: 'Who would you like to meet?',
          builder: (context, onNext) =>
              StepLookingFor(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: 'Your Interests',
          subtitle: 'What makes you, you?',
          builder: (context, onNext) =>
              StepBioInterests(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: 'Add Photos',
          subtitle: 'Show off your best self',
          builder: (context, onNext) => StepPhotos(
            data: _data,
            isLoading: busy,
            onComplete: onNext,
          ),
        ),
      ],
    );
  }

  Future<void> _registerNewAccount() async {
    setState(() => _isUploading = true);

    try {
      final locationResult = await LocationService().getCurrentPosition();
      if (!mounted) return;

      if (!locationResult.success) {
        setState(() => _isUploading = false);
        _showLocationError(locationResult.error ?? 'Failed to get location');
        return;
      }

      _data.latitude = locationResult.latitude;
      _data.longitude = locationResult.longitude;

      final photoUrls = await _uploadPhotosForRegistration();
      if (!mounted) return;

      if (photoUrls.isEmpty) {
        setState(() => _isUploading = false);
        showAuthSnackBar(
          context,
          message: 'Failed to upload photos. Please try again.',
          type: AuthSnackBarType.error,
        );
        return;
      }

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
      if (!mounted) return;
      setState(() => _isUploading = false);

      if (success) {
        await _draft.clear();
        if (!mounted) return;
        setState(() => _registrationComplete = true);
      }
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

  Future<List<String>> _uploadPhotosForRegistration() async {
    if (_data.photoFiles.isEmpty) return [];

    final userService = UserService();

    String tempPath;
    try {
      tempPath = (await getTemporaryDirectory()).path;
    } catch (_) {
      // path_provider is unavailable on some simulators.
      tempPath = Directory.systemTemp.path;
    }

    // Index each file so compression paths stay stable and collision-free
    // even though the uploads run concurrently.
    final indexOf = <File, int>{};
    for (var i = 0; i < _data.photoFiles.length; i++) {
      indexOf[_data.photoFiles[i]] = i;
    }

    return const PhotoUploader().upload(
      _data.photoFiles,
      uploadOne: (file, {required bool isPrimary}) async {
        final i = indexOf[file] ?? 0;
        try {
          final compressed = await const PhotoCompressor()
              .compress(file, tempDir: tempPath, index: i);

          final result = await userService.uploadPhotoForRegistration(
            compressed,
            isPrimary: isPrimary,
          );

          if (result.success && result.data != null) {
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
              await LocationService().openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

/// Which step a resumed draft should open on.
///
/// The password is deliberately never persisted (see [RegistrationDraft]), and
/// step 0 is the only place one is entered. Resuming past it left `_data.password`
/// empty all the way into `register()`, which the server rejects with a 422 the
/// user cannot see or escape. So a draft without a password restarts at step 0 —
/// everything else the user already typed is still restored.
///
/// Extracted so the rule is unit-testable independent of the widget.
int resumeStepFor({
  required String password,
  required int savedStep,
  required int totalSteps,
}) {
  if (password.isEmpty) return 0;
  return savedStep.clamp(0, totalSteps - 1);
}
