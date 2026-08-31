import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// A smart image widget that can handle both network URLs and base64 data URIs
class SmartImage extends StatelessWidget {
  final String imageSource;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;

  /// The width this image will actually be drawn at, in logical pixels.
  ///
  /// Required rather than optional, deliberately: an unsized decode holds a
  /// full-resolution bitmap to fill a thumbnail, and making the slow version
  /// merely discouraged did not work — every call site outside chat had it.
  /// See `core/image/avatar_provider.dart`, which made the same call for the
  /// same reason.
  final double decodeWidth;

  const SmartImage({
    super.key,
    required this.imageSource,
    required this.decodeWidth,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  bool get isBase64 => imageSource.startsWith('data:');

  @override
  Widget build(BuildContext context) {
    final decodePixels =
        (decodeWidth * MediaQuery.devicePixelRatioOf(context)).round();
    if (isBase64) {
      return _buildBase64Image(decodePixels);
    }
    return _buildNetworkImage(decodePixels);
  }

  Widget _buildBase64Image(int decodePixels) {
    try {
      // Extract base64 data from data URI
      // Format: data:image/jpeg;base64,/9j/4AAQ...
      final base64Data = imageSource.split(',').last;
      final bytes = base64Decode(base64Data);

      return Image.memory(
        bytes,
        fit: fit,
        width: width,
        height: height,
        cacheWidth: decodePixels,
        errorBuilder: (context, error, stackTrace) {
          return errorWidget ?? _defaultErrorWidget();
        },
      );
    } catch (e) {
      return errorWidget ?? _defaultErrorWidget();
    }
  }

  Widget _buildNetworkImage(int decodePixels) {
    return CachedNetworkImage(
      imageUrl: imageSource,
      fit: fit,
      width: width,
      height: height,
      memCacheWidth: decodePixels,
      placeholder: (context, url) => placeholder ?? _defaultPlaceholder(),
      errorWidget: (context, url, error) => errorWidget ?? _defaultErrorWidget(),
    );
  }

  Widget _defaultPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _defaultErrorWidget() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[300],
      child: const Icon(
        Icons.broken_image_outlined,
        color: Colors.grey,
      ),
    );
  }
}

/// Extension to check if a string is a base64 data URI
extension ImageSourceExtension on String {
  bool get isBase64DataUri => startsWith('data:');

  /// Get the actual image provider for this source
  ImageProvider toImageProvider() {
    if (isBase64DataUri) {
      try {
        final base64Data = split(',').last;
        return MemoryImage(base64Decode(base64Data));
      } catch (e) {
        // Return a placeholder if decoding fails
        return const AssetImage('assets/images/placeholder.png');
      }
    }
    return CachedNetworkImageProvider(this);
  }
}

/// Helper function to get ImageProvider from a URL or base64 string
ImageProvider? getImageProvider(String? imageSource) {
  if (imageSource == null || imageSource.isEmpty) return null;
  return imageSource.toImageProvider();
}
