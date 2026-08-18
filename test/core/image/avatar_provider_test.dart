import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/image/avatar_provider.dart';

void main() {
  test('null and empty sources yield no provider', () {
    expect(avatarProvider(null, diameter: 40, devicePixelRatio: 3), isNull);
    expect(avatarProvider('', diameter: 40, devicePixelRatio: 3), isNull);
  });

  test('a network url decodes at the displayed size, not full resolution', () {
    final p = avatarProvider('https://x/a.jpg', diameter: 40, devicePixelRatio: 3);

    expect(p, isA<ResizeImage>());
    final resize = p! as ResizeImage;
    expect(resize.width, 120, reason: '40 logical px at dpr 3');
    expect(resize.imageProvider, isA<CachedNetworkImageProvider>());
  });

  test('two calls for the same url and size are equal, so the cache hits', () {
    final a = avatarProvider('https://x/a.jpg', diameter: 40, devicePixelRatio: 3);
    final b = avatarProvider('https://x/a.jpg', diameter: 40, devicePixelRatio: 3);

    expect(a, b);
  });

  test('a different size is a different cache entry', () {
    final small = avatarProvider('https://x/a.jpg', diameter: 40, devicePixelRatio: 3);
    final large = avatarProvider('https://x/a.jpg', diameter: 100, devicePixelRatio: 3);

    expect(small, isNot(large));
  });

  test('a base64 data uri is downscaled too', () {
    // A 1x1 transparent GIF — enough to prove the branch is wrapped without
    // depending on a decoder.
    const uri = 'data:image/gif;base64,'
        'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
    final p = avatarProvider(uri, diameter: 40, devicePixelRatio: 2);

    expect(p, isA<ResizeImage>());
    final resize = p! as ResizeImage;
    expect(resize.width, 80);
    expect(resize.imageProvider, isA<MemoryImage>());
  });
}
