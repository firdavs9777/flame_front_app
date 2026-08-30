import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/widgets/bio_suggestions.dart';

// The point of the widget is that nothing is written without a tap, and that
// what lands in the field is ordinary editable text.
void main() {
  final used = <String>[];

  Widget host({
    List<String> interests = const ['Travel'],
    Locale locale = const Locale('en'),
  }) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: BioSuggestions(interests: interests, onUse: used.add),
        ),
      );

  setUp(used.clear);

  testWidgets('nothing is drafted until the button is tapped', (tester) async {
    await tester.pumpWidget(host());
    expect(find.byKey(const Key('bio_suggestion_0')), findsNothing);
  });

  testWidgets('tapping drafts three, and says they are a starting point',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('bio_suggest_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bio_suggestion_0')), findsOneWidget);
    expect(find.byKey(const Key('bio_suggestion_2')), findsOneWidget);
    expect(find.textContaining('sounds like you'), findsOneWidget);
  });

  testWidgets('picking one hands it to the caller — and only then',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.byKey(const Key('bio_suggest_button')));
    await tester.pumpAndSettle();
    expect(used, isEmpty, reason: 'showing a draft is not choosing it');

    await tester.tap(find.byKey(const Key('bio_suggestion_1')));
    await tester.pumpAndSettle();

    expect(used, hasLength(1));
    expect(used.single, isNotEmpty);
  });

  testWidgets('the drafts are in the reader\'s language, interests included',
      (tester) async {
    // The app ships 32 locales, and the interest names are localised too — a
    // Korean speaker gets a Korean sentence about 여행, not "Travel".
    await tester.pumpWidget(host(locale: const Locale('ko')));
    await tester.tap(find.byKey(const Key('bio_suggest_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('여행'), findsWidgets);
    expect(find.textContaining('Travel'), findsNothing);
  });

  testWidgets('an off-catalogue interest still produces a draft',
      (tester) async {
    // Registration accepted free text, so stored values exist the catalogue
    // has never heard of.
    await tester.pumpWidget(host(interests: const ['Speleology']));
    await tester.tap(find.byKey(const Key('bio_suggest_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Speleology'), findsWidgets);
  });

  testWidgets('with nothing selected it says so instead of drafting',
      (tester) async {
    // On the registration step the bio field sits above the interest picker,
    // so this is reachable, and "no interests" is a state rather than a bug.
    await tester.pumpWidget(host(interests: const []));
    await tester.tap(find.byKey(const Key('bio_suggest_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('bio_suggest_error')), findsOneWidget);
    expect(find.byKey(const Key('bio_suggestion_0')), findsNothing);
  });
}
