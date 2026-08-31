import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/story.dart';
import 'package:flame/providers/story_provider.dart';
import 'package:flame/widgets/smart_image.dart';
import 'package:flame/screens/stories/widgets/story_progress_bar.dart';

/// Full-screen story viewer. Plays through [users][initialUserIndex]'s active
/// stories, then advances to the next user, then closes. Supports 5s
/// auto-advance, tap-zones (prev/next), hold-to-pause, and swipe-down dismiss.
class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.users,
    required this.initialUserIndex,
  });

  final List<UserStories> users;
  final int initialUserIndex;

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const _storyDuration = Duration(seconds: 5);

  late int _userIndex;
  int _storyIndex = 0;
  double _dragDy = 0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _userIndex = widget.initialUserIndex;
    _controller = AnimationController(vsync: this, duration: _storyDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _next();
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Story> get _stories => widget.users[_userIndex].activeStories;
  Story get _current => _stories[_storyIndex];

  void _start() {
    // Record the view (best-effort; refreshes tray rings).
    ref.read(storyActionsProvider).markViewed(_current.id);
    _controller
      ..reset()
      ..forward();
  }

  void _next() {
    if (_storyIndex < _stories.length - 1) {
      setState(() => _storyIndex++);
      _start();
      return;
    }
    // Advance to the next user with active stories.
    var nextUser = _userIndex + 1;
    while (nextUser < widget.users.length &&
        widget.users[nextUser].activeStories.isEmpty) {
      nextUser++;
    }
    if (nextUser < widget.users.length) {
      setState(() {
        _userIndex = nextUser;
        _storyIndex = 0;
      });
      _start();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _prev() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _start();
      return;
    }
    var prevUser = _userIndex - 1;
    while (prevUser >= 0 && widget.users[prevUser].activeStories.isEmpty) {
      prevUser--;
    }
    if (prevUser >= 0) {
      setState(() {
        _userIndex = prevUser;
        _storyIndex = widget.users[prevUser].activeStories.length - 1;
      });
      _start();
    } else {
      // Already at the very first story — restart it.
      _start();
    }
  }

  void _onTapUp(TapUpDetails details) {
    final width = MediaQuery.of(context).size.width;
    if (details.localPosition.dx < width * 0.3) {
      _prev();
    } else {
      _next();
    }
  }

  void _pause() => _controller.stop();
  void _resume() {
    if (!_controller.isAnimating) _controller.forward();
  }

  void _onVerticalDragUpdate(DragUpdateDetails d) {
    if (d.primaryDelta == null) return;
    setState(() => _dragDy = (_dragDy + d.primaryDelta!).clamp(0, 400));
    if (_dragDy > 0) _pause();
  }

  void _onVerticalDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    if (_dragDy > 100 || velocity > 500) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _dragDy = 0);
      _resume();
    }
  }

  Widget _storyImage(String url) {
    if (url.startsWith('http') || url.startsWith('data:')) {
      return SmartImage(
        decodeWidth: MediaQuery.sizeOf(context).width,
        imageSource: url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return Image.file(
      File(url),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.users[_userIndex];
    final story = _current;
    final opacity = (1 - _dragDy / 400).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: _onTapUp,
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, _dragDy),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(child: _storyImage(story.mediaUrl)),
                // Top scrim for legibility.
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 140,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black54, Colors.transparent],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Column(
                      children: [
                        AnimatedBuilder(
                          animation: _controller,
                          builder: (context, _) => StoryProgressBar(
                            count: _stories.length,
                            currentIndex: _storyIndex,
                            progress: _controller.value,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _Header(
                          name: user.name,
                          avatarUrl: user.avatarUrl,
                          createdAt: story.createdAt,
                          onClose: () => Navigator.of(context).maybePop(),
                        ),
                      ],
                    ),
                  ),
                ),
                if (story.caption != null && story.caption!.isNotEmpty)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 40,
                    child: Text(
                      story.caption!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.avatarUrl,
    required this.createdAt,
    required this.onClose,
  });

  final String name;
  final String avatarUrl;
  final DateTime createdAt;
  final VoidCallback onClose;

  String get _timeAgo {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    return '${diff.inHours}h';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: Colors.white24,
          backgroundImage:
              avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
          child: avatarUrl.isEmpty
              ? const Icon(Icons.person, color: Colors.white, size: 20)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _timeAgo,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onClose,
          icon: const Icon(Icons.close, color: Colors.white),
        ),
      ],
    );
  }
}
