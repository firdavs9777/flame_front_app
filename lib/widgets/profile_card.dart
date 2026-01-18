import 'package:flutter/material.dart';
import 'package:flame/models/models.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/smart_image.dart';

class ProfileCard extends StatefulWidget {
  final User user;
  final VoidCallback? onTap;

  const ProfileCard({
    super.key,
    required this.user,
    this.onTap,
  });

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
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
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
                child: SmartImage(
                  imageSource: widget.user.photos[_currentPhotoIndex],
                  fit: BoxFit.cover,
                  placeholder: Container(
                    color: Colors.grey[300],
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  errorWidget: Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.person, size: 100, color: Colors.grey),
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
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // Online indicator
              if (widget.user.isOnline)
                Positioned(
                  top: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.successColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: Colors.white),
                        SizedBox(width: 5),
                        Text(
                          'Online',
                          style: TextStyle(
                            color: Colors.white,
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
                        Colors.black.withValues(alpha: 0.8),
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
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.verified,
                          color: Colors.blue,
                          size: 24,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Colors.white70,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.user.distanceText,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.user.bio,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
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
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            interest,
                            style: const TextStyle(
                              color: Colors.white,
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
