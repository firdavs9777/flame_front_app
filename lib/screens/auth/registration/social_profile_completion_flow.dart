import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/image/photo_compressor.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/screens/auth/widgets/auth_snackbar.dart';
import 'package:flame/services/location_service.dart';
import 'package:flame/services/user_service.dart';
import 'location_gate.dart';
import 'photo_uploader.dart';
import 'registration_flow.dart';
import 'step_wizard.dart';
import 'steps/step_bio_interests.dart';
import 'steps/step_looking_for.dart';
import 'steps/step_photos.dart';
import 'steps/step_profile_info.dart';

/// Profile completion for a user who signed in with Google, Apple or Facebook.
///
/// The same wizard registration uses, minus the email/password step — a social
/// user already has credentials. No exit: they are authenticated but their
/// profile is unusable, so backing out would strand them between the two.
class SocialProfileCompletionFlow extends ConsumerStatefulWidget {
  const SocialProfileCompletionFlow({super.key});

  @override
  ConsumerState<SocialProfileCompletionFlow> createState() =>
      _SocialProfileCompletionFlowState();
}

class _SocialProfileCompletionFlowState
    extends ConsumerState<SocialProfileCompletionFlow> {
  final RegistrationData _data = RegistrationData();
  bool _isUploading = false;
  bool _prefilled = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    // Pre-fill the name the provider gave us — once. Doing this unconditionally
    // in build() meant every rebuild fought whatever the user had typed.
    if (!_prefilled && authState.user != null) {
      _data.name = authState.user!.name;
      _prefilled = true;
    }

    return StepWizard(
      isBusy: _isUploading,
      onComplete: _completeSocialProfile,
      steps: [
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
          builder: (context, onNext) =>
              StepBioInterests(data: _data, onNext: onNext),
        ),
        WizardStep(
          title: context.l10n.registerStepPhotosTitle,
          subtitle: context.l10n.registerStepPhotosSubtitle,
          builder: (context, onNext) => StepPhotos(
            data: _data,
            isLoading: _isUploading,
            onComplete: onNext,
          ),
        ),
      ],
    );
  }

  Future<void> _completeSocialProfile() async {
    setState(() => _isUploading = true);
    final userService = UserService();

    try {
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
          message: profileResult.error ?? context.l10n.registerProfileUpdateFailed,
          type: AuthSnackBarType.error,
        );
        return;
      }

      // A social account is created without coordinates, and the backend does
      // not call a profile complete without them (app/core/profile.py). This
      // flow is the only place they can be established up front — Discover's
      // LocationRefresher is enrichment for accounts that already have a point,
      // and no-ops after one attempt per session.
      //
      // Best-effort all the same, for the reason the photo step is: this wizard
      // has no exit, so an authenticated user must be able to finish. A refusal
      // costs them nearby matches until they grant it, not the ability to leave
      // this screen. Runs after the profile PATCH so a failing profile does not
      // spend the permission prompt for nothing.
      final location = await const LocationGate().establish(
        getPosition: LocationService().getCurrentPosition,
        push: (latitude, longitude) async {
          final result = await userService.updateLocation(
            latitude: latitude,
            longitude: longitude,
          );
          return result.success;
        },
      );
      if (!mounted) return;

      if (!location.ok) {
        // Two different situations: no fix means the permission is the fix and
        // settings is the right advice; a rejected push means we HAVE the
        // coordinates and the server refused them, which settings cannot help.
        showAuthSnackBar(
          context,
          message: location.failure == LocationGateFailure.push
              ? context.l10n.registerLocationSaveFailed
              : context.l10n.registerLocationDeniedWarning,
          type: AuthSnackBarType.warning,
        );
      }

      final uploaded = await _uploadPhotos(userService);
      if (!mounted) return;

      // The profile PATCH already succeeded and this wizard has no exit — an
      // authenticated user must be able to finish even if every photo upload
      // failed. Warn instead of blocking; they can add photos from their
      // profile afterward.
      if (_data.photoFiles.isNotEmpty && uploaded.isEmpty) {
        showAuthSnackBar(
          context,
          message: context.l10n.registerPhotoUploadFailedSocial,
          type: AuthSnackBarType.warning,
        );
      }

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
        message: context.l10n.registerGenericError(e.toString()),
        type: AuthSnackBarType.error,
      );
    }
  }

  /// The same uploader registration uses — parallel, with one retry per photo.
  /// This path was a sequential `for` loop that swallowed every error, which is
  /// exactly the drift a shared wizard is meant to stop.
  ///
  /// Returns the URLs that made it, in `_data.photoFiles` order — an empty
  /// list is a real "nothing uploaded" result, which the caller checks against
  /// `_data.photoFiles` to decide whether to warn.
  Future<List<String>> _uploadPhotos(UserService userService) async {
    if (_data.photoFiles.isEmpty) return const [];

    String tempPath;
    try {
      final dir = await Directory.systemTemp.createTemp('flame_photos');
      tempPath = dir.path;
    } catch (_) {
      tempPath = Directory.systemTemp.path;
    }

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
          final result =
              await userService.uploadPhoto(compressed, isPrimary: isPrimary);
          if (result.success) {
            return UploadOutcome(success: true, url: result.data?.url);
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
}
