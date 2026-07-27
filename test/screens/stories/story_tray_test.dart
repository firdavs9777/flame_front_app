import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/models/story.dart';
import 'package:flame/providers/story_provider.dart';
import 'package:flame/screens/stories/widgets/story_tray.dart';
import 'package:flame/screens/stories/widgets/story_gradient_ring.dart';

UserStories _userWithStory({required String name, bool viewed = false}) {
  final created = DateTime.now().subtract(const Duration(hours: 2));
  return UserStories(
    userId: name,
    name: name,
    avatarUrl: '',
    stories: [
      Story(
        id: '${name}_0',
        userId: name,
        mediaUrl: 'x',
        createdAt: created,
        expiresAt: created.add(const Duration(hours: 24)),
        hasViewed: viewed,
      ),
    ],
  );
}

Future<void> _pumpTray(WidgetTester tester, StoriesFeed feed) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storiesFeedProvider.overrideWith((ref) async => feed),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: kSupportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: StoryTray()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the own "Your story" item and matched users', (tester) async {
    await _pumpTray(
      tester,
      StoriesFeed(others: [_userWithStory(name: 'Ann')]),
    );

    expect(find.text('Your story'), findsOneWidget);
    expect(find.text('Ann'), findsOneWidget);
  });

  testWidgets('renders a gradient ring per unseen user + the own item', (tester) async {
    await _pumpTray(
      tester,
      StoriesFeed(others: [
        _userWithStory(name: 'Ann', viewed: false),
        _userWithStory(name: 'Bea', viewed: true),
      ]),
    );

    // Own ring + one per matched user = 3 rings.
    expect(find.byType(StoryGradientRing), findsNWidgets(3));
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Bea'), findsOneWidget);
  });
}
