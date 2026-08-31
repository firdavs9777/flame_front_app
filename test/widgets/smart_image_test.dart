import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/widgets/smart_image.dart';

void main() {
  testWidgets('passes a decode width derived from the draw width and DPR',
      (tester) async {
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 100,
        height: 100,
        child: SmartImage(
          imageSource: 'https://cdn/a.webp',
          decodeWidth: 100,
        ),
      ),
    ));

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    // Physical pixels: what the device rasterises, not what layout calls it.
    expect(image.memCacheWidth, 300);
  });

  testWidgets('renders a data URI without hitting the network', (tester) async {
    const onePixelPng =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

    await tester.pumpWidget(const MaterialApp(
      home: SmartImage(imageSource: onePixelPng, decodeWidth: 100),
    ));

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });
}
