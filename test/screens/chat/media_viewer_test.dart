import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/screens/chat/media_viewer_screen.dart';

// A photo in a chat used to render at a hardcoded 200px with BoxFit.cover and
// no tap target, so there was no way to see it at any size larger than a
// cropped thumbnail. It also used raw Image.network: no cache, so scrolling
// refetched it, and no decode sizing, so a 10MB photo decoded at full
// resolution into a 200px slot.
void main() {
  const url = 'https://example.com/photo.jpg';

  Widget host(Widget child) => MaterialApp(home: child);

  testWidgets('renders the image through the cache, not a raw network fetch', (
    tester,
  ) async {
    await tester.pumpWidget(host(const MediaViewerScreen(url: url)));

    expect(
      find.byType(CachedNetworkImage),
      findsOneWidget,
      reason: 'the viewer must reuse the bytes the bubble already downloaded',
    );
  });

  testWidgets('is zoomable', (tester) async {
    await tester.pumpWidget(host(const MediaViewerScreen(url: url)));

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );

    expect(viewer.maxScale, greaterThan(1.0),
        reason: 'seeing detail is the entire point of opening the image');
    expect(viewer.minScale, lessThanOrEqualTo(1.0));
  });

  testWidgets('offers a way out', (tester) async {
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MediaViewerScreen(url: url)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    // pump(), not pumpAndSettle(): the placeholder spinner never stops
    // animating because CachedNetworkImage cannot resolve in a test, so
    // pumpAndSettle would wait for a quiescence that never arrives.
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MediaViewerScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MediaViewerScreen), findsNothing,
        reason: 'a full-screen viewer with no visible close control traps the user');
  });

  testWidgets('animates from the bubble when given a hero tag', (tester) async {
    await tester.pumpWidget(
      host(const MediaViewerScreen(url: url, heroTag: 'msg-1')),
    );

    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, 'msg-1');
  });

  testWidgets('works without a hero tag', (tester) async {
    // Two messages can carry the same image URL, so the tag is the message id
    // and callers that have none must still get a working viewer rather than a
    // duplicate-tag crash.
    await tester.pumpWidget(host(const MediaViewerScreen(url: url)));

    expect(tester.takeException(), isNull);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });
}
