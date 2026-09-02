import 'package:flutter/material.dart';
import 'package:flame/models/models.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/smart_image.dart';
import 'package:flame/core/format/distance_display.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/theme/app_tokens.dart';
import 'package:flame/core/image/photo_variants.dart';
import 'package:flame/widgets/language_flag_badge.dart';
import 'package:flame/widgets/languages_line.dart';

class ProfileCard extends StatefulWidget {
  final User user;
  final VoidCallback? onTap;

  const ProfileCard({super.key, required this.user, this.onTap});

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  int _currentPhotoIndex = 0;

  void _nextPhoto() {
    if (_currentPhotoIndex < widget.user.photos.length - 1) {
      setState(() => _currentPhotoIndex++);
    }
  }

  void _previousPhoto() {
    if (_currentPhotoIndex > 0) {
      setState(() => _currentPhotoIndex--);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Formatted here rather than on the model: rendering a distance needs
    // localisations and a locale, which are a widget's business.
    final km = widget.user.distance;
    final distanceAway = km == null
        ? null
        : formatDistanceAway(
            km,
            context.l10n,
            Localizations.localeOf(context).toString(),
          );

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: context.viewerScrim.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo
              GestureDetector(
                onTapUp: (details) {
                  final width = context.size?.width ?? 0;
                  if (details.localPosition.dx < width / 2) {
                    _previousPhoto();
                  } else {
                    _nextPhoto();
                  }
                },
                child: widget.user.photos.isEmpty
                    ? Container(
                        color: context.fill,
                        child: Center(
                          child: Icon(
                            Icons.person,
                            size: 100,
                            color: context.secondaryText,
                          ),
                        ),
                      )
                    : SmartImage(
                        // Full-bleed card: the draw width is the screen width.
                        decodeWidth: MediaQuery.sizeOf(context).width,
                        imageSource: photoUrlFor(
                          widget.user.photos[_currentPhotoIndex.clamp(
                            0,
                            widget.user.photos.length - 1,
                          )],
                          PhotoSize.full,
                        ),
                        fit: BoxFit.cover,
                        placeholder: Container(
                          color: context.fill,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: Container(
                          color: context.fill,
                          child: Icon(
                            Icons.person,
                            size: 100,
                            color: context.secondaryText,
                          ),
                        ),
                      ),
              ),

              // Photo indicators
              if (widget.user.photos.length > 1)
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Row(
                    children: List.generate(
                      widget.user.photos.length,
                      (index) => Expanded(
                        child: Container(
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: index == _currentPhotoIndex
                                ? context.onOverlay
                                : context.onOverlay.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Language flag badge — the premise, legible without reading.
              // Top-left mirrors the online indicator's top-right so neither
              // collides with the name/distance/bio block anchored at the
              // bottom of the card.
              LanguageFlagBadge(
                code: widget.user.languagesSpoken.isEmpty
                    ? null
                    : widget.user.languagesSpoken.first,
                offset: 20,
                alignment: Alignment.topLeft,
              ),

              // Online indicator
              if (widget.user.isOnline)
                Positioned(
                  top: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: context.onOverlay),
                        SizedBox(width: 5),
                        Text(
                          context.l10n.presenceOnline,
                          style: TextStyle(
                            color: context.onOverlay,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Gradient overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        context.viewerScrim.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
              ),

              // User info
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${widget.user.name}, ${widget.user.age}',
                          style: TextStyle(
                            color: context.onOverlay,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.verified,
                          color: AppColors.verifiedBadge,
                          size: 24,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    // Omitted entirely when there is no distance to show. The
                    // old code could only render a number, which is why every
                    // card said "0 km away".
                    if (distanceAway != null) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            color: context.onOverlay.withValues(alpha: 0.7),
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              distanceAway,
                              style: TextStyle(
                                color: context.onOverlay.withValues(alpha: 0.7),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    // The premise, made visible, right beside the distance
                    // label it sits under. LanguagesLine renders nothing of
                    // its own accord when nothing is declared, so the
                    // conditional here only owns the spacing around it.
                    if (widget.user.languagesSpoken.isNotEmpty ||
                        widget.user.languagesLearning.isNotEmpty) ...[
                      LanguagesLine(
                        spoken: widget.user.languagesSpoken,
                        learning: widget.user.languagesLearning,
                        style: TextStyle(
                          color: context.onOverlay.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      widget.user.bio,
                      style: TextStyle(color: context.onOverlay, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: widget.user.interests.take(4).map((interest) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: context.onOverlay.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            interest,
                            style: TextStyle(
                              color: context.onOverlay,
                              fontSize: 12,
                            ),
                          ),
                        );
                      }).toList(),
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
}
