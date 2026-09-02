import 'package:flame/core/navigation/app_routes.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flame/providers/location_provider.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';
import 'package:flame/widgets/smart_image.dart';
import 'package:flame/core/format/distance_display.dart';
import 'package:flame/core/interests/interest_catalogue.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/screens/settings/widgets/settings_section.dart';
import 'package:flame/screens/profile/photo_gallery.dart';
import 'package:flame/core/image/avatar_provider.dart';
import 'package:flame/core/image/photo_variants.dart';
import 'package:flame/models/photo.dart';
import 'package:flame/core/image/upload_limits.dart';
import 'package:flame/widgets/languages_line.dart';

class MyProfileScreen extends ConsumerStatefulWidget {
  const MyProfileScreen({super.key});

  @override
  ConsumerState<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends ConsumerState<MyProfileScreen> {
  bool _refreshingLocation = false;

  /// User-initiated location refresh.
  ///
  /// Uses refreshNow rather than refresh: the throttle and the
  /// do-not-ask-again-after-a-denial rule both exist to stop the app nagging,
  /// and neither applies to someone who has just tapped the button. Tapping it
  /// and having nothing happen would read as broken.
  Future<void> _refreshLocation(BuildContext context) async {
    if (_refreshingLocation) return;
    setState(() => _refreshingLocation = true);

    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    final ok = await ref.read(locationRefresherProvider).refreshNow();
    // Re-read the profile so the new city appears without leaving the screen.
    if (ok) await ref.read(currentUserProvider.notifier).loadUser();

    if (!mounted) return;
    setState(() => _refreshingLocation = false);
    messenger.showSnackBar(SnackBar(
      content: Text(
        ok ? l10n.profileLocationUpdated : l10n.profileLocationFailed,
      ),
    ));
  }

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        ref.read(currentUserProvider.notifier).loadUser();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(currentUserProvider);
    final matchesState = ref.watch(matchesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.profileMyProfile),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.l10n.navSettings,
            onPressed: () => Navigator.pushNamed(
              context,
              AppRoutes.settings,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.pushNamed(
                context,
                AppRoutes.editProfile,
              );
            },
          ),
        ],
      ),
      body: userState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 60, color: context.secondaryText),
              const SizedBox(height: 16),
              Text(
                context.l10n.profileLoadFailed,
                style: TextStyle(color: context.secondaryText),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  ref.read(currentUserProvider.notifier).loadUser();
                },
                child: Text(context.l10n.retry),
              ),
            ],
          ),
        ),
        data: (user) {
          if (user == null) {
            return Center(child: Text(context.l10n.profileNoUserData));
          }

          final matchCount = matchesState.maybeWhen(
            data: (matches) => matches.length,
            orElse: () => 0,
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Profile picture
                Stack(
                  children: [
                    // The avatar views; the camera badge on it changes. Both
                    // used to open the picker, so there was no way to actually
                    // look at your own main photo.
                    GestureDetector(
                      key: const Key('profile_avatar'),
                      onTap: user.photos.isEmpty
                          ? null
                          : () => openPhotoGallery(context, user.photos, 0),
                      child: CircleAvatar(
                        radius: 60,
                        backgroundImage: avatarProviderFor(
                          user.primaryPhoto,
                          diameter: 120,
                          devicePixelRatio:
                              MediaQuery.devicePixelRatioOf(context),
                        ),
                        child: user.photos.isEmpty
                            ? const Icon(Icons.person, size: 60)
                            : null,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => _showPhotoOptions(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: context.surface,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            color: context.onPrimary,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${user.name}, ${user.age}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (user.isVerified) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.verified,
                        key: const Key('verified_badge'),
                        color: AppTheme.primaryColor,
                        size: 22,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // The location line, with the means to fix it beside it.
                //
                // Until place names were stored this read "Unknown" for every
                // user, permanently — the model's fallback for a city the
                // server never populated. It is now real, which is also why it
                // needs a way to be corrected: a city resolved once in another
                // town is worse than no city.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        user.location == 'Unknown'
                            ? context.l10n.profileLocationUnknown
                            : user.location,
                        key: const Key('profile_location'),
                        style: TextStyle(
                            fontSize: 16, color: context.secondaryText),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    _LocationRefreshButton(
                      onRefresh: () => _refreshLocation(context),
                    ),
                  ],
                ),
                if (user.languagesSpoken.isNotEmpty ||
                    user.languagesLearning.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  LanguagesLine(
                    spoken: user.languagesSpoken,
                    learning: user.languagesLearning,
                    style:
                        TextStyle(fontSize: 14, color: context.secondaryText),
                  ),
                ],
                if (user.isPremiumActive) ...[
                  const SizedBox(height: 10),
                  Container(
                    key: const Key('premium_badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.workspace_premium,
                          color: context.onPrimary,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          context.l10n.profilePremium,
                          style: TextStyle(
                            color: context.onPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 30),

                // Stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStat(context.l10n.profilePhotos, user.photos.length.toString()),
                    _buildStat(context.l10n.profileInterests, user.interests.length.toString()),
                    _buildStat(context.l10n.navMatches, matchCount.toString()),
                  ],
                ),
                const SizedBox(height: 30),

                // Photos grid
                _buildSection(
                  title: context.l10n.profilePhotos,
                  editKey: const Key('profile_edit_photos'),
                  onEdit: () =>
                      Navigator.pushNamed(context, AppRoutes.editProfile),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: user.photos.length + 1,
                    itemBuilder: (context, index) {
                      if (index == user.photos.length) {
                        return _buildAddPhotoButton();
                      }
                      return _buildPhotoTile(user.photos, index);
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // Bio
                _buildSection(
                  title: context.l10n.profileAboutMe,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.fill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      user.bio,
                      style: const TextStyle(fontSize: 16, height: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Interests
                _buildSection(
                  title: context.l10n.profileInterests,
                  editKey: const Key('profile_edit_interests'),
                  onEdit: () =>
                      Navigator.pushNamed(context, AppRoutes.editProfile),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: user.interests.map((interest) {
                      return Chip(
                        label: Text(interestLabel(interest, context.l10n)),
                        backgroundColor: AppTheme.primaryColor.withValues(
                          alpha: 0.1,
                        ),
                        labelStyle: TextStyle(color: AppTheme.primaryColor),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 30),

                // The cheapest way a user notices their own profile is thin
                // before concluding the app is broken.
                SettingsRow(
                  title: context.l10n.profilePreview,
                  subtitle: context.l10n.profilePreviewSubtitle,
                  leading: const Icon(Icons.visibility_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  // isPreview must survive this: without it the viewer is
                  // shown like and pass buttons for their own profile.
                  onTap: () => Navigator.pushNamed(
                    context,
                    AppRoutes.profileDetail,
                    arguments: ProfileDetailArgs(user: user, isPreview: true),
                  ),
                ),
                const SizedBox(height: 20),

                // Preferences — read-only here. Displaying a value edited
                // elsewhere is not duplication; a second editor is. Tapping opens
                // the Discover filter sheet, which owns them.
                InkWell(
                  onTap: () =>
                      Navigator.pushNamed(context, '/discover/filters'),
                  child: _buildSection(
                    title: context.l10n.profileDiscoveryPreferences,
                    child: Column(
                      children: [
                        _buildPreferenceRow(
                          context.l10n.profileLookingFor,
                          user.lookingFor.displayName,
                        ),
                        _buildPreferenceRow(
                          context.l10n.filterAgeRange,
                          context.l10n.filterAgeRangeValue(
                            user.minAgePreference,
                            user.maxAgePreference,
                          ),
                        ),
                        _buildPreferenceRow(
                          context.l10n.filterDistance,
                          // Same formatter the editor seeds its field from, so
                          // a stored 24.6 does not read "24 km" here and "24.6"
                          // one tap away.
                          formatDistanceValue(
                            user.maxDistancePreference,
                            context.l10n,
                            Localizations.localeOf(context).toString(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 14, color: context.secondaryText),
        ),
      ],
    );
  }

  /// A titled block, optionally with a way to go and edit what it shows.
  ///
  /// Read-only sections that hold editable content are a dead end otherwise:
  /// Photos and Interests both render values the user owns, and neither gave
  /// any indication that Edit Profile was where you change them.
  Widget _buildSection({
    required String title,
    required Widget child,
    VoidCallback? onEdit,
    Key? editKey,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (onEdit != null)
              TextButton.icon(
                key: editKey,
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(context.l10n.profileEditProfile),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }

  /// A photo that opens full screen when tapped.
  ///
  /// It had no `onTap` at all: tapping your own photo on your own profile did
  /// nothing, while the "+" tile beside it opened the picker. The one gesture
  /// everyone tries was the one gesture that was not wired up.
  Widget _buildPhotoTile(List<Photo> photos, int index) {
    return GestureDetector(
      key: Key('profile_photo_$index'),
      onTap: () => openPhotoGallery(context, photos, index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SmartImage(
          imageSource: photoUrlFor(photos[index], PhotoSize.medium),
          // A 3-across grid, so a tile is roughly a third of the screen.
          decodeWidth: MediaQuery.sizeOf(context).width / 3,
          fit: BoxFit.cover,
          placeholder: Container(color: context.fill),
          errorWidget: Container(
            color: context.fill,
            child: const Icon(Icons.error),
          ),
        ),
      ),
    );
  }

  Widget _buildAddPhotoButton() {
    return GestureDetector(
      onTap: () => _showPhotoOptions(context),
      child: Container(
        decoration: BoxDecoration(
          color: context.fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.divider,
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Icon(Icons.add, size: 40, color: context.secondaryText),
      ),
    );
  }

  void _showPhotoOptions(BuildContext context) {
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(context.l10n.profileTakePhoto),
              onTap: () async {
                Navigator.pop(context);
                final photo = await picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: kProfilePhotoMaxEdge.toDouble(),
                  maxHeight: kProfilePhotoMaxEdge.toDouble(),
                  imageQuality: kUploadQuality,
                );
                if (photo != null) {
                  _uploadPhoto(File(photo.path));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(context.l10n.profileChooseFromGallery),
              onTap: () async {
                Navigator.pop(context);
                final photo = await picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: kProfilePhotoMaxEdge.toDouble(),
                  maxHeight: kProfilePhotoMaxEdge.toDouble(),
                  imageQuality: kUploadQuality,
                );
                if (photo != null) {
                  _uploadPhoto(File(photo.path));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadPhoto(File photo) async {
    final user = ref.read(currentUserProvider).valueOrNull;
    final isPrimary = user?.photos.isEmpty ?? true;

    final success = await ref
        .read(currentUserProvider.notifier)
        .uploadPhoto(photo, isPrimary: isPrimary);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.profilePhotoUploaded)),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.profilePhotoUploadFailed)));
      }
    }
  }

  Widget _buildPreferenceRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 16, color: context.secondaryText),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}


/// The refresh affordance beside the location line.
///
/// A quiet icon rather than a labelled button: this sits under someone's name
/// on their own profile, and the common case is that the city is already
/// right. It should be findable, not prominent.
class _LocationRefreshButton extends StatelessWidget {
  const _LocationRefreshButton({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('profile_refresh_location'),
      onPressed: onRefresh,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(),
      padding: const EdgeInsets.all(4),
      tooltip: context.l10n.profileLocationUpdate,
      icon: Icon(
        Icons.my_location,
        size: 18,
        color: context.secondaryText,
      ),
    );
  }
}
