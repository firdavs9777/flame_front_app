import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Full-screen, zoomable view of a chat image.
///
/// Chat photos used to render at a hardcoded 200px with `BoxFit.cover` and no
/// tap target, so there was no way to see one at any size larger than a cropped
/// thumbnail — you could receive a photo and never actually look at it.
///
/// Scale bounds and the cached-image source match BananaTalk's own
/// `pages/moments/viewer/image_viewer.dart`, so the two apps behave the same
/// way in the hands of someone who uses both.
class MediaViewerScreen extends StatelessWidget {
  final String url;

  /// Ties the thumbnail to the full-screen image so it expands out of the
  /// bubble instead of cutting to a new screen. Callers pass the message id;
  /// null is fine, and necessary when two messages share one image URL, since
  /// duplicate Hero tags in a single tree throw.
  final String? heroTag;

  const MediaViewerScreen({super.key, required this.url, this.heroTag});

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      // contain, not cover: the whole point of opening it is to see all of it.
      placeholder: (_, __) => const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
      ),
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 64),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: heroTag == null
                    ? image
                    : Hero(tag: heroTag!, child: image),
              ),
            ),
          ),
          // A full-screen black surface with no visible way out strands anyone
          // who does not know the back gesture.
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
