import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/screens/chat/media_viewer_screen.dart';

// A photo in a chat used to render at a hardcoded 200px with BoxFit.cover and
// no tap target, so there was no way to see it at any size larger than a
// cropped thumbnail. It also used raw Image.network: no cache, so scrolling
// refetched it, and no decode sizing, so a 10MB photo decoded at full
// resolution into a 200px slot.
void main() {
  _galleryTests();

  const url = 'https://example.com/photo.jpg';

  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: child,
      );

  testWidgets('renders the image through the cache, not a raw network fetch', (
    tester,
  ) async {
    await tester.pumpWidget(host(MediaViewerScreen(url: url)));

    expect(
      find.byType(CachedNetworkImage),
      findsOneWidget,
      reason: 'the viewer must reuse the bytes the bubble already downloaded',
    );
  });

  testWidgets('is zoomable', (tester) async {
    await tester.pumpWidget(host(MediaViewerScreen(url: url)));

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
              MaterialPageRoute(builder: (_) => MediaViewerScreen(url: url)),
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
      host(MediaViewerScreen(url: url, heroTag: 'msg-1')),
    );

    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, 'msg-1');
  });

  testWidgets('works without a hero tag', (tester) async {
    // Two messages can carry the same image URL, so the tag is the message id
    // and callers that have none must still get a working viewer rather than a
    // duplicate-tag crash.
    await tester.pumpWidget(host(MediaViewerScreen(url: url)));

    expect(tester.takeException(), isNull);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
  });
}

// The same viewer now serves a profile's photos. A profile grid tile had no
// onTap at all, so tapping your own photo did nothing; the fix reuses this
// screen rather than growing a second one that would drift from its zoom
// bounds, scrim and close button.
void _galleryTests() {
  const photos = [
    'https://example.com/a.jpg',
    'https://example.com/b.jpg',
    'https://example.com/c.jpg',
  ];

  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: child,
      );

  group('gallery', () {
    testWidgets('opens on the photo that was tapped, not the first', (
      tester,
    ) async {
      await tester.pumpWidget(host(
        const MediaViewerScreen.gallery(urls: photos, initialIndex: 2),
      ));
      await tester.pump();

      expect(find.text('3 of 3'), findsOneWidget);
    });

    testWidgets('swiping moves to the next photo and the counter follows', (
      tester,
    ) async {
      await tester.pumpWidget(host(
        const MediaViewerScreen.gallery(urls: photos),
      ));
      await tester.pump();
      expect(find.text('1 of 3'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      // Not pumpAndSettle: the placeholder spinner never stops, so settling
      // waits forever on an image that will never load in a test.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('2 of 3'), findsOneWidget);
    });

    testWidgets('a single image shows no counter and does not page', (
      tester,
    ) async {
      // A chat photo is a gallery of one. It must behave exactly as before:
      // nothing to count, and no horizontal drag competing with the zoom.
      await tester.pumpWidget(host(MediaViewerScreen(url: photos.first)));
      await tester.pump();

      expect(find.byKey(const Key('media_viewer_position')), findsNothing);

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.physics, isA<NeverScrollableScrollPhysics>());
    });

    testWidgets('an out-of-range initial index opens rather than throwing', (
      tester,
    ) async {
      // Never worth crashing a viewer over which photo it opened on.
      await tester.pumpWidget(host(
        const MediaViewerScreen.gallery(urls: photos, initialIndex: 99),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('3 of 3'), findsOneWidget);
    });

    testWidgets('the hero rides only the page that opened', (tester) async {
      // A Hero on a page the user swiped to would fly the image in from a
      // thumbnail it never came out of.
      await tester.pumpWidget(host(
        const MediaViewerScreen.gallery(
          urls: photos,
          initialIndex: 1,
          heroTag: 'tag-1',
        ),
      ));
      await tester.pump();

      expect(find.byType(Hero), findsOneWidget);
    });
  });
}
