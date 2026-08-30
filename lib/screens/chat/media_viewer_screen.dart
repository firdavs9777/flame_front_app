import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/theme/app_tokens.dart';

/// Full-screen, zoomable view of an image, or of a gallery of them.
///
/// Chat photos used to render at a hardcoded 200px with `BoxFit.cover` and no
/// tap target, so there was no way to see one at any size larger than a cropped
/// thumbnail — you could receive a photo and never actually look at it. Profile
/// photos had the same problem for longer: the grid on your own profile had no
/// `onTap` at all, so tapping your own photo did nothing whatsoever.
///
/// One screen serves both because they are the same job. A chat photo is a
/// gallery of one; a profile is a gallery of up to six, paged by swiping. The
/// alternative was a second viewer that would drift away from this one's zoom
/// bounds, scrim colour and close affordance.
///
/// Scale bounds and the cached-image source match BananaTalk's own
/// `pages/moments/viewer/image_viewer.dart`, so the two apps behave the same
/// way in the hands of someone who uses both.
class MediaViewerScreen extends StatefulWidget {
  /// The images to page through. Never empty.
  final List<String> urls;

  /// Which of [urls] opens first.
  final int initialIndex;

  /// Ties the thumbnail to the full-screen image so it expands out of the
  /// bubble instead of cutting to a new screen. Callers pass the message id;
  /// null is fine, and necessary when two messages share one image URL, since
  /// duplicate Hero tags in a single tree throw.
  ///
  /// Only the page that opened carries it: animating a Hero onto a page the
  /// user swiped to would fly the image in from a thumbnail it never left.
  final String? heroTag;

  /// A single image — a chat photo, or anything else with nothing to page to.
  MediaViewerScreen({super.key, required String url, this.heroTag})
      : urls = [url],
        initialIndex = 0;

  /// A set of images to page through — a profile's photos.
  ///
  /// No assert on emptiness: `List.length` is not const-evaluable, so one here
  /// would cost every caller the `const`. An empty list is handled below
  /// instead, which is the better outcome anyway — a viewer is not worth
  /// crashing a screen over.
  const MediaViewerScreen.gallery({
    super.key,
    required this.urls,
    this.initialIndex = 0,
    this.heroTag,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    // An out-of-range index from a caller must not throw in a viewer; it is
    // never worth crashing a screen over which photo it opened on. Nor is an
    // empty list, which clamp(0, -1) would otherwise turn into a range error.
    _index = widget.urls.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.urls.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _image(String url) => CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        // contain, not cover: the whole point of opening it is to see all of it.
        placeholder: (_, __) => Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.onOverlay.withValues(alpha: 0.54),
          ),
        ),
        errorWidget: (_, __, ___) => Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: context.onOverlay.withValues(alpha: 0.38),
            size: 64,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final multiple = widget.urls.length > 1;

    return Scaffold(
      backgroundColor: context.viewerScrim,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _controller,
              // A single image keeps its old behaviour exactly: no horizontal
              // drag to fight the zoom gesture over.
              physics: multiple
                  ? const PageScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final image = _image(widget.urls[i]);
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: widget.heroTag == null || i != widget.initialIndex
                        ? image
                        : Hero(tag: widget.heroTag!, child: image),
                  ),
                );
              },
            ),
          ),
          // A full-screen black surface with no visible way out strands anyone
          // who does not know the back gesture.
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: IconButton(
                icon: Icon(Icons.close, color: context.onOverlay),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              ),
            ),
          ),
          if (multiple)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      context.l10n.profilePhotoPosition(
                        _index + 1,
                        widget.urls.length,
                      ),
                      key: const Key('media_viewer_position'),
                      style: TextStyle(
                        color: context.onOverlay.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
