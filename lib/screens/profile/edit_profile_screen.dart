import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';
import 'package:flame/widgets/smart_image.dart';
import 'package:flame/models/models.dart';
import 'package:flame/core/format/distance_format.dart';

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

/// Saves discovery preferences. `showDistance` is deliberately not a
/// parameter: the Preferences section renders no control for it (see
/// `_PreferencesSection`), so nothing here ever needs to carry it.
typedef PreferencesSave = Future<bool> Function({
  int? minAge,
  int? maxAge,
  double? maxDistance,
  bool? showOnlineStatus,
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
  final PreferencesSave? savePreferences;

  const EditProfileScreen({
    super.key,
    this.saveAbout,
    this.saveInterests,
    this.savePreferences,
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

  Future<bool> _defaultSavePreferences({
    int? minAge,
    int? maxAge,
    double? maxDistance,
    bool? showOnlineStatus,
  }) {
    return ref.read(currentUserProvider.notifier).updatePreferences(
          minAge: minAge,
          maxAge: maxAge,
          maxDistance: maxDistance,
          showOnlineStatus: showOnlineStatus,
        );
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: userState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (user) {
          if (user == null) {
            return const Center(child: Text('No user data'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionCard(
                  title: 'Photos',
                  child: _PhotosSection(user: user),
                ),
                const SizedBox(height: 20),
                _SectionCard(
                  title: 'About',
                  child: _AboutSection(
                    user: user,
                    onSave: widget.saveAbout ?? _defaultSaveAbout,
                  ),
                ),
                const SizedBox(height: 20),
                _SectionCard(
                  title: 'Interests',
                  child: _InterestsSection(
                    user: user,
                    onSave: widget.saveInterests ?? _defaultSaveInterests,
                  ),
                ),
                const SizedBox(height: 20),
                _SectionCard(
                  title: 'Preferences',
                  child: _PreferencesSection(
                    user: user,
                    onSave: widget.savePreferences ?? _defaultSavePreferences,
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
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration(BuildContext context, String hint) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: context.fill,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );
}

/// A Save button in `AppTheme.primaryColor`, with [context.onPrimary] as its
/// foreground — text and spinner sit ON a primary-coloured surface.
///
/// [buttonKey] goes on the `ElevatedButton` itself rather than on this
/// wrapper: the wrapper's render object is the enclosing `Align`, which
/// spans the full row width, so a tap computed against its center would
/// land beside the (right-aligned) button rather than on it.
class _SaveButton extends StatelessWidget {
  final Key buttonKey;
  final bool isSaving;
  final VoidCallback? onPressed;

  const _SaveButton({
    required this.buttonKey,
    required this.isSaving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton(
        key: buttonKey,
        onPressed: isSaving ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: context.onPrimary,
        ),
        child: isSaving
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.onPrimary,
                ),
              )
            : const Text('Save'),
      ),
    );
  }
}

Widget _fieldLabel(BuildContext context, String label) {
  return Text(
    label,
    style: TextStyle(fontWeight: FontWeight.w600, color: context.onSurface),
  );
}

/// Photos grid. Both actions it offers (upload, delete) save immediately
/// against the backend, so there is no separate Save button here — the
/// section is independent by construction.
///
/// It offers no reordering. An earlier "Set as main photo" item called
/// `CurrentUserNotifier.setMainPhotoAt`, and `PATCH /users/me/photos/reorder`
/// does exist and does persist — but its response serialises each photo as
/// `{id, order, is_primary}` with no `url`, while `Photo.fromJson` defaults a
/// missing url to `''`. So the tap reported "Main photo updated" and then
/// blanked the url of every photo in local state, emptying the grid until the
/// next `loadUser()`. Removed rather than papered over: making it work means
/// either the backend including `url` in that payload, or `setMainPhotoAt`
/// reordering the lists it already holds instead of trusting the response.
/// Both are a change to the contract, not to this widget.
class _PhotosSection extends ConsumerStatefulWidget {
  final User user;

  const _PhotosSection({required this.user});

  @override
  ConsumerState<_PhotosSection> createState() => _PhotosSectionState();
}

class _PhotosSectionState extends ConsumerState<_PhotosSection> {
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPhotosGrid(widget.user),
        if (_isUploading) ...[
          const SizedBox(height: 12),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }

  Widget _buildPhotosGrid(User user) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 6,
      itemBuilder: (context, index) {
        if (index < user.photos.length) {
          return _buildPhotoTile(user.photos[index], index);
        }
        return _buildAddPhotoButton(index);
      },
    );
  }

  Widget _buildPhotoTile(String photoUrl, int index) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SmartImage(
            imageSource: photoUrl,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => _showPhotoOptions(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.54),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.more_vert,
                color: context.onOverlay,
                size: 16,
              ),
            ),
          ),
        ),
        if (index == 0)
          Positioned(
            bottom: 4,
            left: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Main',
                style: TextStyle(
                  color: context.onPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAddPhotoButton(int index) {
    return GestureDetector(
      onTap: () => _pickPhoto(index),
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
        child: Icon(
          Icons.add_a_photo,
          size: 32,
          color: context.secondaryText,
        ),
      ),
    );
  }

  void _showPhotoOptions(int index) {
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete photo', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                final ok = await ref
                    .read(currentUserProvider.notifier)
                    .deletePhotoAt(index);
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Photo deleted' : 'Could not delete photo'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto(int index) async {
    final picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take a photo'),
              onTap: () async {
                Navigator.pop(context);
                final photo = await picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 1024,
                  maxHeight: 1024,
                  imageQuality: 85,
                );
                if (photo != null) {
                  _uploadPhoto(File(photo.path));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () async {
                Navigator.pop(context);
                final photo = await picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1024,
                  maxHeight: 1024,
                  imageQuality: 85,
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
    setState(() => _isUploading = true);

    final user = ref.read(currentUserProvider).valueOrNull;
    final isPrimary = user?.photos.isEmpty ?? true;

    final success = await ref.read(currentUserProvider.notifier).uploadPhoto(
      photo,
      isPrimary: isPrimary,
    );

    if (!mounted) return;
    setState(() => _isUploading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Photo uploaded successfully'
            : 'Failed to upload photo'),
      ),
    );
  }
}

/// Name, age and bio. Validates locally before calling [onSave] — an
/// invalid age or too-short name never reaches it — and keeps the user's
/// typed values on screen if the save fails, since [onSave] failing doesn't
/// touch [User] state at all.
class _AboutSection extends StatefulWidget {
  final User user;
  final AboutSave onSave;

  const _AboutSection({required this.user, required this.onSave});

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _bioController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name);
    _ageController = TextEditingController(text: widget.user.age.toString());
    _bioController = TextEditingController(text: widget.user.bio);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final ok = await widget.onSave(
      name: _nameController.text.trim(),
      age: int.parse(_ageController.text),
      bio: _bioController.text,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'About updated' : 'Could not save — try again')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(context, 'Name'),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('about_name_field'),
            controller: _nameController,
            decoration: _fieldDecoration(context, 'Your name'),
            // Both bounds are the route's own: User.name is minlength 2,
            // maxlength 50. Only the floor was checked, so a 60-character
            // name went out and came back as a bare "Could not save".
            validator: (value) {
              final name = (value ?? '').trim();
              if (name.length < 2) {
                return 'Name must be at least 2 characters';
              }
              if (name.length > 50) {
                return 'Name must be 50 characters or fewer '
                    '(currently ${name.length})';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _fieldLabel(context, 'Age'),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('about_age_field'),
            controller: _ageController,
            keyboardType: TextInputType.number,
            decoration: _fieldDecoration(context, 'Your age'),
            validator: (value) {
              final age = int.tryParse(value ?? '');
              if (age == null || age < 18 || age > 100) {
                return 'Enter a valid age (18-100)';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _fieldLabel(context, 'About Me'),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('about_bio_field'),
            controller: _bioController,
            maxLines: 4,
            maxLength: 500,
            decoration: _fieldDecoration(context, 'Tell others about yourself...'),
          ),
          const SizedBox(height: 8),
          _SaveButton(
            buttonKey: const Key('about_save_button'),
            isSaving: _isSaving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// Looking-for gender and interest tags, saved together — the pair the
/// original form always submitted as one unit.
///
/// This section has no `Form` because it has no text fields, which is how it
/// ended up as the one section in a form-validation task with no validation at
/// all: the route requires 1 to 10 interests
/// (`interests: Field(min_length=1, max_length=10)`), while the picker offers
/// 16 chips with no floor and no cap. Deselecting your last interest, or
/// picking an eleventh, produced a bare "Could not save — try again" with no
/// hint as to which. [_boundsError] is checked before [onSave] is called, and
/// names the bound that was hit.
class _InterestsSection extends StatefulWidget {
  final User user;
  final InterestsSave onSave;

  const _InterestsSection({required this.user, required this.onSave});

  @override
  State<_InterestsSection> createState() => _InterestsSectionState();
}

class _InterestsSectionState extends State<_InterestsSection> {
  static const _allInterests = [
    'Travel', 'Music', 'Movies', 'Sports', 'Fitness', 'Food',
    'Art', 'Gaming', 'Reading', 'Photography', 'Coffee', 'Hiking',
    'Dancing', 'Cooking', 'Yoga', 'Nature',
  ];

  /// The route's own bounds on `interests`.
  static const _minInterests = 1;
  static const _maxInterests = 10;

  late Gender? _lookingFor;
  late List<String> _selectedInterests;
  String? _boundsError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _lookingFor = widget.user.lookingFor;
    _selectedInterests = List<String>.from(widget.user.interests);
  }

  /// Names the bound that was hit, or null when the selection is savable.
  String? _validate() {
    final count = _selectedInterests.length;
    if (count < _minInterests) {
      return 'Pick at least $_minInterests interest';
    }
    if (count > _maxInterests) {
      return 'Pick at most $_maxInterests interests — $count are selected';
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      setState(() => _boundsError = error);
      return;
    }

    setState(() {
      _boundsError = null;
      _isSaving = true;
    });
    final ok = await widget.onSave(
      lookingFor: _lookingFor,
      interests: _selectedInterests,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Interests updated' : 'Could not save — try again'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(context, 'Looking For'),
        const SizedBox(height: 12),
        _buildGenderSelector(context),
        const SizedBox(height: 20),
        _fieldLabel(context, 'Interests'),
        const SizedBox(height: 12),
        _buildInterestsSelector(context),
        if (_boundsError != null) ...[
          const SizedBox(height: 8),
          Text(
            _boundsError!,
            key: const Key('interests_bounds_error'),
            style: TextStyle(color: AppTheme.errorColor, fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        _SaveButton(
          buttonKey: const Key('interests_save_button'),
          isSaving: _isSaving,
          onPressed: _save,
        ),
      ],
    );
  }

  Widget _buildGenderSelector(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: Gender.values.map((gender) {
        final isSelected = _lookingFor == gender;
        return GestureDetector(
          onTap: () => setState(() => _lookingFor = gender),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryColor : context.fill,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              gender.displayName,
              style: TextStyle(
                color: isSelected ? context.onPrimary : context.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInterestsSelector(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _allInterests.map((interest) {
        final isSelected = _selectedInterests.contains(interest);
        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedInterests.remove(interest);
              } else {
                _selectedInterests.add(interest);
              }
              // Re-evaluate a message already on screen so it tracks the
              // selection instead of going stale, but don't surface one before
              // the user has asked to save.
              if (_boundsError != null) _boundsError = _validate();
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryColor.withValues(alpha: 0.1)
                  : context.fill,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? AppTheme.primaryColor : context.divider,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Text(
              interest,
              style: TextStyle(
                color: isSelected ? AppTheme.primaryColor : context.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Discovery preferences: min age, max age, max distance, and "Show online
/// status" — deliberately NOT "Show distance". `showDistance` is stored and
/// saveable server-side, but `discoveryService.toDiscoverUser` hardcodes
/// `distance: 0`, so a toggle here would govern a number that always reads
/// zero. That is the dead-button pattern this codebase has already spent
/// effort removing twice; it becomes real the day distance itself does.
///
/// Validates min age <= max age before calling [onSave], matching the
/// route's own refine — catching it here saves a round trip and a 422.
class _PreferencesSection extends StatefulWidget {
  final User user;
  final PreferencesSave onSave;

  const _PreferencesSection({required this.user, required this.onSave});

  @override
  State<_PreferencesSection> createState() => _PreferencesSectionState();
}

class _PreferencesSectionState extends State<_PreferencesSection> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _minAgeController;
  late final TextEditingController _maxAgeController;
  late final TextEditingController _maxDistanceController;
  late bool _showOnlineStatus;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _minAgeController =
        TextEditingController(text: widget.user.minAgePreference.toString());
    _maxAgeController =
        TextEditingController(text: widget.user.maxAgePreference.toString());
    _maxDistanceController = TextEditingController(
      text: formatDistance(widget.user.maxDistancePreference),
    );
    _showOnlineStatus = widget.user.showOnlineStatus;
  }

  @override
  void dispose() {
    _minAgeController.dispose();
    _maxAgeController.dispose();
    _maxDistanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final ok = await widget.onSave(
      minAge: int.parse(_minAgeController.text),
      maxAge: int.parse(_maxAgeController.text),
      maxDistance: double.parse(_maxDistanceController.text),
      showOnlineStatus: _showOnlineStatus,
    );
    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Preferences updated' : 'Could not save — try again'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(context, 'Minimum Age'),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('preferences_min_age_field'),
            controller: _minAgeController,
            keyboardType: TextInputType.number,
            decoration: _fieldDecoration(context, 'Minimum age'),
            validator: (value) {
              final age = int.tryParse(value ?? '');
              if (age == null || age < 18 || age > 100) {
                return 'Enter a valid age (18-100)';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _fieldLabel(context, 'Maximum Age'),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('preferences_max_age_field'),
            controller: _maxAgeController,
            keyboardType: TextInputType.number,
            decoration: _fieldDecoration(context, 'Maximum age'),
            validator: (value) {
              final age = int.tryParse(value ?? '');
              if (age == null || age < 18 || age > 100) {
                return 'Enter a valid age (18-100)';
              }
              final minAge = int.tryParse(_minAgeController.text);
              if (minAge != null && age < minAge) {
                return 'Must be at least the minimum age';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          _fieldLabel(context, 'Maximum Distance (km)'),
          const SizedBox(height: 8),
          TextFormField(
            key: const Key('preferences_max_distance_field'),
            controller: _maxDistanceController,
            keyboardType: TextInputType.number,
            decoration: _fieldDecoration(context, 'Maximum distance'),
            // Bounds taken from the route's own schema, which is
            // `max_distance: Optional[int] = Field(ge=1, le=500)`
            // (flame_backend app/community/schemas.py:100). The ceiling was
            // not checked at all, so 5000 went out and came back as a bare
            // "Could not save". The floor was already effectively right; it
            // now names the bound instead of saying "valid".
            //
            // NOTE: that schema types the field `int`, so a fractional value
            // like 24.6 is a 422 even though this field accepts one and Task 6
            // deliberately stopped rounding it. Not changed here — see the
            // report; it is a contract question, not a widget question.
            validator: (value) {
              final distance = double.tryParse(value ?? '');
              if (distance == null) {
                return 'Enter a distance in kilometres';
              }
              if (distance < 1) {
                return 'Minimum distance is 1 km';
              }
              if (distance > 500) {
                return 'Maximum distance is 500 km';
              }
              return null;
            },
          ),
          SwitchListTile(
            key: const Key('preferences_show_online_switch'),
            contentPadding: EdgeInsets.zero,
            title: Text('Show online status', style: TextStyle(color: context.onSurface)),
            subtitle: Text(
              'Let others see when you\'re active',
              style: TextStyle(color: context.secondaryText),
            ),
            value: _showOnlineStatus,
            activeColor: AppTheme.primaryColor,
            onChanged: (value) => setState(() => _showOnlineStatus = value),
          ),
          const SizedBox(height: 8),
          _SaveButton(
            buttonKey: const Key('preferences_save_button'),
            isSaving: _isSaving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
