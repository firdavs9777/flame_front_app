import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/navigation/app_router.dart';
import 'package:flame/core/navigation/app_routes.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/user.dart';
import 'package:flame/screens/chat/media_viewer_screen.dart';
import 'package:flame/screens/settings/notification_settings_screen.dart';
import 'package:flame/screens/profile/profile_detail_screen.dart';

User _user() => User.fromJson({'id': 'u1', 'name': 'Bea', 'photos': <dynamic>[]});

Future<void> _pumpAndGo(
  WidgetTester tester,
  String routeName, {
  Object? arguments,
  /// MediaViewerScreen draws a CachedNetworkImage, and settling it waits on a
  /// network fetch the test binding refuses. A single frame is enough: the
  /// question here is which screen the route built, not what it painted.
  bool settle = true,
}) async {
  final key = GlobalKey<NavigatorState>();
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      navigatorKey: key,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: const SizedBox.shrink(),
    ),
  ));
  key.currentState!.pushNamed(routeName, arguments: arguments);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('every name resolves', () {
    test('onGenerateRoute returns a route for all of AppRoutes.all', () {
      for (final name in AppRoutes.all) {
        final route = AppRouter.onGenerateRoute(RouteSettings(
          name: name,
          arguments: _argumentsFor(name),
        ));
        expect(route, isNotNull, reason: '$name resolved to nothing');
      }
    });
  });

  group('a disabled feature is not reachable by name', () {
    Future<void> pumpNotificationSettings(WidgetTester tester) async {
      final route = AppRouter.onGenerateRoute(
        const RouteSettings(name: AppRoutes.notificationSettings),
      ) as MaterialPageRoute;

      // ProviderScope because the Android branch really does build
      // NotificationSettingsScreen now, and it watches a provider. The
      // not-found branch does not need one, but sharing the host keeps the two
      // cases differing only in the platform, which is the variable under test.
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(builder: (context) => route.builder(context)),
        ),
      ));
      await tester.pump();
    }

    // try/finally rather than addTearDown: testWidgets asserts that every
    // foundation debug variable is back to null when the body returns, and
    // tear-downs run after that check. Leaving it to addTearDown fails the
    // test it was meant to clean up after.
    Future<void> onPlatform(
      TargetPlatform platform,
      Future<void> Function() body,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('notification settings open on $platform, where push works',
          (tester) async {
        // flutter_test reports Android by default, so both are set explicitly:
        // the platform is the variable under test, not an ambient default.
        await onPlatform(platform, () async {
          await pumpNotificationSettings(tester);

          expect(find.byType(NotificationSettingsScreen), findsOneWidget);
          expect(find.byType(RouteNotFoundScreen), findsNothing);
        });
      });
    }

    testWidgets('they resolve to not-found where push cannot arrive',
        (tester) async {
      // The Settings row is hidden on desktop, but hiding an entry point does
      // not close a screen — a deep link, a restored stack, or a notification
      // payload can still name the route.
      await onPlatform(TargetPlatform.macOS, () async {
        await pumpNotificationSettings(tester);

        expect(find.byType(RouteNotFoundScreen), findsOneWidget);
        expect(find.byType(NotificationSettingsScreen), findsNothing);
      });
    });
  });

  group('the fallback', () {
    testWidgets('an unknown name renders not-found instead of throwing',
        (tester) async {
      // A stale notification payload naming a route that no longer exists is a
      // normal event, not a crash.
      await _pumpAndGo(tester, '/this/route/never/existed');
      expect(find.byType(RouteNotFoundScreen), findsOneWidget);
    });

    testWidgets('a null name renders not-found', (tester) async {
      final route = AppRouter.onGenerateRoute(const RouteSettings(name: null));
      expect(route, isNotNull);
    });

    testWidgets('the wrong argument type renders not-found, not a cast error',
        (tester) async {
      // Arguments arrive as Object? and can be anything — a malformed payload
      // must not take the app down.
      await _pumpAndGo(tester, AppRoutes.mediaViewer,
          arguments: 'not-args', settle: false);
      expect(find.byType(RouteNotFoundScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('missing arguments render not-found', (tester) async {
      await _pumpAndGo(tester, AppRoutes.profileDetail);
      expect(find.byType(RouteNotFoundScreen), findsOneWidget);
    });
  });

  group('typed destinations', () {
    testWidgets('profileDetail reaches the screen with its user',
        (tester) async {
      await _pumpAndGo(tester, AppRoutes.profileDetail,
          arguments: ProfileDetailArgs(user: _user()));

      final screen =
          tester.widget<ProfileDetailScreen>(find.byType(ProfileDetailScreen));
      expect(screen.user.id, 'u1');
      expect(screen.isPreview, isFalse);
    });

    testWidgets('profileDetail carries isPreview through', (tester) async {
      // The one argument whose loss is silent and wrong: a preview showing the
      // viewer their own like and pass buttons.
      await _pumpAndGo(tester, AppRoutes.profileDetail,
          arguments: ProfileDetailArgs(user: _user(), isPreview: true));

      final screen =
          tester.widget<ProfileDetailScreen>(find.byType(ProfileDetailScreen));
      expect(screen.isPreview, isTrue);
    });

    testWidgets('mediaViewer reaches the screen with url and heroTag',
        (tester) async {
      await _pumpAndGo(tester, AppRoutes.mediaViewer,
          arguments: const MediaViewerArgs(url: 'https://x/y.jpg', heroTag: 'h1'),
          settle: false);

      final screen =
          tester.widget<MediaViewerScreen>(find.byType(MediaViewerScreen));
      expect(screen.urls, ['https://x/y.jpg']);
      expect(screen.heroTag, 'h1');
    });
  });
}

/// Valid arguments per route, so the exhaustive sweep exercises the real branch
/// rather than every route's fallback.
Object? _argumentsFor(String name) {
  switch (name) {
    case AppRoutes.profileDetail:
      return ProfileDetailArgs(user: _user());
    case AppRoutes.chat:
      return const ChatRouteArgs.id('c1');
    case AppRoutes.mediaViewer:
      return const MediaViewerArgs(url: 'https://x/y.jpg', heroTag: 'h1');
    case AppRoutes.storyViewer:
      return const StoryViewerArgs(users: [], initialUserIndex: 0);
    case AppRoutes.languagePicker:
      return LanguagePickerArgs(
        initialSelection: const [],
        maxSelection: 3,
        onDone: (_) {},
      );
    default:
      return null;
  }
}
