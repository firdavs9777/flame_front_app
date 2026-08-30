import 'package:flutter/material.dart';
import 'package:flame/screens/profile/edit_profile/section_chrome.dart';
import 'package:flame/screens/profile/edit_profile/photos_section.dart';
import 'package:flame/screens/profile/edit_profile/interests_section.dart';
import 'package:flame/screens/profile/edit_profile/about_section.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/models/models.dart';
import 'package:flame/core/i18n/build_context_ext.dart';

/// Saves the About section (name, age, bio) — nothing else. The signature is
/// the independence guarantee: this function has no parameter through which
/// preferences or interests could travel along for the ride.
typedef AboutSave = Future<bool> Function({
  required String name,
  required int age,
  required String bio,
});

/// Saves who the user is looking for together with their interest tags.
typedef InterestsSave = Future<bool> Function({
  required Gender? lookingFor,
  required List<String> interests,
});


/// A form split into independently-saving section cards — Photos, About,
/// Interests, Preferences — each validating before it calls its save
/// callback rather than discovering a bad value after a request already
/// went out.
///
/// The three save callbacks are injected, the way `ChatSearchScreen` takes
/// `search`, so the screen (and each section) is drivable in a test without
/// a network. Left null — the case for every real navigation site in the
/// app — each section falls back to the matching `CurrentUserNotifier`
/// method.
class EditProfileScreen extends ConsumerStatefulWidget {
  final AboutSave? saveAbout;
  final InterestsSave? saveInterests;

  const EditProfileScreen({
    super.key,
    this.saveAbout,
    this.saveInterests,
  });

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  Future<bool> _defaultSaveAbout({
    required String name,
    required int age,
    required String bio,
  }) {
    return ref.read(currentUserProvider.notifier).updateProfile(
          name: name,
          age: age,
          bio: bio,
        );
  }

  Future<bool> _defaultSaveInterests({
    required Gender? lookingFor,
    required List<String> interests,
  }) {
    return ref.read(currentUserProvider.notifier).updateProfile(
          lookingFor: lookingFor,
          interests: interests,
        );
  }


  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.profileEditProfile)),
      body: userState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(context.l10n.errorWithDetail('$error'))),
        data: (user) {
          if (user == null) {
            return Center(child: Text(context.l10n.profileNoUserData));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionCard(
                  title: context.l10n.profilePhotos,
                  child: PhotosSection(user: user),
                ),
                const SizedBox(height: 20),
                SectionCard(
                  title: context.l10n.profileAbout,
                  child: AboutSection(
                    user: user,
                    onSave: widget.saveAbout ?? _defaultSaveAbout,
                  ),
                ),
                const SizedBox(height: 20),
                SectionCard(
                  title: context.l10n.profileInterests,
                  child: InterestsSection(
                    user: user,
                    onSave: widget.saveInterests ?? _defaultSaveInterests,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Shared chrome for every section: a titled card on [BuildContext.surface].
