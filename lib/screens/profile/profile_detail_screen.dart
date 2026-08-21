import 'package:flutter/material.dart';
import 'package:flame/models/models.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/theme/app_tokens.dart';
import 'package:flame/widgets/smart_image.dart';
import 'package:flame/widgets/report_block_menu.dart';
import 'package:flame/core/format/distance_display.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/providers/swipe_provider.dart';
import 'package:flame/screens/settings/widgets/settings_snackbar.dart';

class ProfileDetailScreen extends ConsumerStatefulWidget {
  final User user;

  /// True when the viewer is looking at their own profile as others see it.
  ///
  /// Hides like, super-like and report: none of them are things you can do to
  /// yourself. Defaults false, so every existing call site is unchanged.
  final bool isPreview;

  const ProfileDetailScreen({
    super.key,
    required this.user,
    this.isPreview = false,
  });

  @override
  ConsumerState<ProfileDetailScreen> createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends ConsumerState<ProfileDetailScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Formatted here rather than on the model: rendering a distance needs
    // localisations and a locale, which are a widget's business.
    final km = widget.user.distance;
    final distanceAway = km == null
        ? null
        : formatDistanceAway(
            km, context.l10n, Localizations.localeOf(context).toString());

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 400,
            pinned: true,
            backgroundColor: AppTheme.primaryColor,
            leading: IconButton(
              icon: CircleAvatar(
                backgroundColor: context.surface,
                child: Icon(Icons.arrow_back, color: context.onSurface),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              // You cannot report or block yourself.
              if (!widget.isPreview)
                ReportBlockMenu(
                  userId: widget.user.id,
                  userName: widget.user.name,
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _pageController,
                    itemCount: widget.user.photos.length,
                    onPageChanged: (page) {
                      setState(() => _currentPage = page);
                    },
                    itemBuilder: (context, index) {
                      return SmartImage(
                        imageSource: widget.user.photos[index],
                        fit: BoxFit.cover,
                        placeholder: Container(
                          color: context.fill,
                        ),
                        errorWidget: Container(
                          color: context.fill,
                          child: const Icon(Icons.person, size: 100),
                        ),
                      );
                    },
                  ),
                  // Photo indicators
                  if (widget.user.photos.length > 1)
                    Positioned(
                      bottom: 80,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          widget.user.photos.length,
                          (index) => Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: index == _currentPage
                                  ? context.onOverlay
                                  : context.onOverlay.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Gradient
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Theme.of(context).colorScheme.shadow.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name and age
                  Row(
                    children: [
                      Text(
                        '${widget.user.name}, ${widget.user.age}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (widget.user.isOnline)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.successColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Online',
                            style: TextStyle(
                              color: context.onOverlay,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Location
                  Row(
                    children: [
                      Icon(Icons.location_on, color: context.secondaryText, size: 18),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                        // Location alone when distance is unknown — no dangling
                        // separator with nothing after it.
                        distanceAway == null
                            ? '${widget.user.location}'
                            : '${widget.user.location} - $distanceAway',
                        style: TextStyle(
                          color: context.secondaryText,
                          fontSize: 14,
                        ),
                      ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Bio
                  const Text(
                    'About',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.user.bio,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Interests
                  const Text(
                    'Interests',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.user.interests.map((interest) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          interest,
                          style: TextStyle(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: widget.isPreview ? null : Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.surface,
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(
                icon: Icons.close,
                color: AppTheme.errorColor,
                onTap: () => Navigator.pop(context),
              ),
              _buildActionButton(
                icon: Icons.star,
                color: AppColors.superLike,
                onTap: _superLike,
              ),
              _buildActionButton(
                icon: Icons.favorite,
                color: AppTheme.successColor,
                onTap: _like,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Likes this profile through the same notifier the deck uses, so a like from a
  /// profile and a like from a swipe are the same operation.
  ///
  /// Deliberately does NOT call discoveryProvider.removeUser: swipeProvider.like
  /// already does that internally, and a second call would be a no-op today and a
  /// bug the moment that provider changes.
  Future<void> _like() => _swipe(
      (notifier) => notifier.like(widget.user));

  Future<void> _superLike() => _swipe(
      (notifier) => notifier.superLike(widget.user));

  Future<void> _swipe(Future<String?> Function(SwipeNotifier) action) async {
    final error = await action(ref.read(swipeProvider.notifier));
    if (!mounted) return;
    if (error != null) {
      showSettingsSnackBar(context,
          message: error, type: SettingsSnackBarType.error);
      return;
    }
    Navigator.pop(context);
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: context.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
          border: Border.all(color: color, width: 2),
        ),
        child: Icon(icon, color: color, size: 28),
      ),
    );
  }
}
