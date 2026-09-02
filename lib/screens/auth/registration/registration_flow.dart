import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
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

  /// ISO 639-1 codes, max 3 each. Spoken is seeded from the device locale the
  /// first time step 4 builds.
  List<String> languagesSpoken = [];
  List<String> languagesLearning = [];

  /// Whether the locale seed has already been offered for this draft.
  ///
  /// It lives here, not in step 4's State, because StepWizard's PageView keeps
  /// no state: advancing to step 5 destroys step 4's State and coming back
  /// builds a new one. A latch on the State therefore re-armed itself, and a
  /// user who had deliberately emptied "Languages you speak" got the device
  /// locale silently re-added on the way back — and then persisted. Seeding is
  /// a once-per-draft event, so it is recorded where the draft is.
  bool languagesSeeded = false;

  List<String> photos = []; // URLs after upload
  List<File> photoFiles = []; // Local files before upload
  double? latitude;
  double? longitude;

  /// Whether the Terms and Privacy box was ticked. Lives here, not only inside
  /// the step's State, because the server has to be told: a checkbox that gates
  /// a button and is then discarded records nothing, and GDPR Art. 7(1) asks
  /// the controller to be able to demonstrate consent.
  bool termsAccepted = false;
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
  int _restoreGeneration = 0;

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
        title: Text(context.l10n.registerResumeTitle),
        content: Text(context.l10n.registerResumeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.registerResumeStartOver),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.registerResumeContinue),
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

  /// The step the wizard is on, so a save triggered from inside a step (rather
  /// than by moving between them) records where the user actually is.
  int _currentStep = 0;

  void _restoreFrom(RegistrationData data, int step) {
    setState(() {
      _data
        ..email = data.email
        ..name = data.name
        ..age = data.age
        ..gender = data.gender
        ..lookingFor = data.lookingFor
        ..bio = data.bio
        ..interests = data.interests
        ..languagesSpoken = data.languagesSpoken
        ..languagesLearning = data.languagesLearning
        ..languagesSeeded = data.languagesSeeded
        ..photoFiles = data.photoFiles
        ..latitude = data.latitude
        ..longitude = data.longitude;
      _restoreGeneration++;
    });

    final resumeAt = resumeStepFor(
      password: _data.password,
      savedStep: step,
      totalSteps: _totalSteps,
    );
    // Set explicitly rather than relying on jumpToStep to report back: if it
    // does not, an in-step save would record step 0 and send a resuming user
    // back to the beginning.
    _currentStep = resumeAt;
    _wizardKey.currentState?.jumpToStep(resumeAt);
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
      onStepChanged: (step) {
        _currentStep = step;
        _draft.save(_data, step);
      },
      onExit: () {
        // Explicit back-out to welcome — discard the saved draft.
        _draft.clear();
        Navigator.of(context).pop();
      },
      onComplete: _registerNewAccount,
      steps: [
        WizardStep(
          title: context.l10n.registerStepAccountTitle,
          subtitle: context.l10n.registerStepAccountSubtitle,
          builder: (context, onNext) => StepEmailPassword(
            key: ValueKey(_restoreGeneration),
            data: _data,
            onNext: onNext,
          ),
        ),
        WizardStep(
          title: context.l10n.registerStepAboutTitle,
          subtitle: context.l10n.registerStepAboutSubtitle,
          builder: (context, onNext) =>
              StepProfileInfo(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: context.l10n.registerStepLookingForTitle,
          subtitle: context.l10n.registerStepLookingForSubtitle,
          builder: (context, onNext) =>
              StepLookingFor(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: context.l10n.registerStepInterestsTitle,
          subtitle: context.l10n.registerStepInterestsSubtitle,
          builder: (context, onNext) => StepBioInterests(
            data: _data,
            onNext: onNext,
            onPersist: () => _draft.save(_data, _currentStep),
          ),
        ),
        WizardStep(
          title: context.l10n.registerStepPhotosTitle,
          subtitle: context.l10n.registerStepPhotosSubtitle,
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
        _showLocationError(
          locationResult.error ?? context.l10n.registerLocationFailed,
        );
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
          message: context.l10n.registerPhotoUploadFailed,
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
            termsAccepted: _data.termsAccepted,
            languagesSpoken: _data.languagesSpoken,
            languagesLearning: _data.languagesLearning,
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
        message: context.l10n.registerGenericError(e.toString()),
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
        title: Text(context.l10n.registerLocationRequiredTitle),
        content: Text(
          '$error\n\n${context.l10n.registerLocationRequiredBody}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.registerCancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await LocationService().openAppSettings();
            },
            child: Text(context.l10n.registerOpenSettings),
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
