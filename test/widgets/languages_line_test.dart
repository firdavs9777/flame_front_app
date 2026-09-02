import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/languages/language.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/providers/languages_provider.dart';
import 'package:flame/widgets/languages_line.dart';

/// LanguagesLine is a ConsumerWidget reading the catalogue, so it needs a
/// ProviderScope. The catalogue is overridden rather than fetched — these
/// tests are about the line, not the network.
Widget _host(Widget child) => ProviderScope(
      overrides: [
        languageCatalogProvider.overrideWith((ref) async => const [
              Language(code: 'ko', name: 'Korean', nativeName: '한국어'),
              Language(code: 'en', name: 'English', nativeName: 'English'),
              Language(code: 'ja', name: 'Japanese', nativeName: '日本語'),
            ]),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('shows spoken and learning languages by their own names',
      (tester) async {
    await tester.pumpWidget(_host(const LanguagesLine(
      spoken: ['ko'],
      learning: ['en'],
    )));

    expect(find.textContaining('한국어'), findsOneWidget);
    expect(find.textContaining('English'), findsOneWidget);
  });

  testWidgets('renders nothing at all when nothing is declared',
      (tester) async {
    // Every existing account. An empty row with a dangling label reads as
    // broken data.
    await tester.pumpWidget(_host(const LanguagesLine(
      spoken: [],
      learning: [],
    )));

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('omits the learning half when only spoken is declared',
      (tester) async {
    await tester.pumpWidget(_host(const LanguagesLine(
      spoken: ['ja'],
      learning: [],
    )));

    expect(find.textContaining('日本語'), findsOneWidget);
    expect(find.textContaining('Learning'), findsNothing);
  });

  testWidgets('an unknown code degrades to the code rather than crashing',
      (tester) async {
    await tester.pumpWidget(_host(const LanguagesLine(
      spoken: ['zz'],
      learning: [],
    )));

    expect(find.textContaining('zz'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
