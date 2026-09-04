import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/languages/language.dart';
import 'package:flame/core/languages/language_complement.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/user.dart';
import 'package:flame/providers/languages_provider.dart';
import 'package:flame/widgets/profile_card.dart';

User _user() => User.fromJson({
      'id': 'u1',
      'name': 'Bea',
      'age': 29,
      'photos': <dynamic>[],
      'languages_spoken': ['ko'],
      'languages_learning': ['en'],
    });

Widget _host(Widget child) => ProviderScope(
      overrides: [
        languageCatalogProvider.overrideWith((ref) async => const [
              Language(code: 'ko', name: 'Korean', nativeName: '한국어'),
              Language(code: 'en', name: 'English', nativeName: 'English'),
            ]),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  Future<void> pumpWith(WidgetTester tester, LanguageComplement? c) async {
    // A tall, narrow box: the card lays out against its constraints, and the
    // default test surface is short enough to overflow the info block.
    await tester.pumpWidget(_host(SizedBox(
      width: 360,
      height: 720,
      child: ProfileCard(user: _user(), complement: c),
    )));
    await tester.pump();
  }

  testWidgets('the badge appears for the mutual case', (tester) async {
    await pumpWith(tester, LanguageComplement.mutual);
    expect(find.text('You can teach each other'), findsOneWidget);
  });

  testWidgets('every weaker rung shows nothing', (tester) async {
    // The badge earns its meaning by being rare. If it appeared for a shared
    // language, or for one-directional teaching, it would be decoration on
    // most cards rather than a reason on a few.
    for (final rung in [
      LanguageComplement.theyTeachYou,
      LanguageComplement.youTeachThem,
      LanguageComplement.shared,
      LanguageComplement.none,
      LanguageComplement.unknown,
    ]) {
      await pumpWith(tester, rung);
      expect(find.text('You can teach each other'), findsNothing,
          reason: '$rung must not be badged');
    }
  });

  testWidgets('an unknown viewer shows nothing rather than guessing',
      (tester) async {
    // What the deck passes while the current user is still loading.
    await pumpWith(tester, null);
    expect(find.text('You can teach each other'), findsNothing);
  });

  testWidgets('the languages themselves still render without a badge',
      (tester) async {
    // The badge explains the line; it must not become a precondition for it.
    await pumpWith(tester, LanguageComplement.shared);
    expect(find.textContaining('한국어'), findsOneWidget);
  });
}
