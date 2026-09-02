import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/languages/language.dart';
import 'package:flame/core/languages/language_fallback.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/providers/languages_provider.dart';
import 'package:flame/screens/languages/language_picker_screen.dart';

final _catalog = [
  const Language(code: 'en', name: 'English', nativeName: 'English'),
  const Language(code: 'ko', name: 'Korean', nativeName: '한국어'),
  const Language(code: 'zu', name: 'Zulu', nativeName: 'isiZulu'),
];

Widget _host({
  required List<String> initial,
  required ValueChanged<List<String>> onDone,
  int max = 3,
}) =>
    ProviderScope(
      overrides: [
        languageCatalogProvider.overrideWith((ref) async => _catalog),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LanguagePickerScreen(
          initialSelection: initial,
          maxSelection: max,
          onDone: onDone,
        ),
      ),
    );

void main() {
  testWidgets('lists languages under their own names', (tester) async {
    await tester.pumpWidget(_host(initial: const [], onDone: (_) {}));
    await tester.pumpAndSettle();

    expect(find.text('한국어'), findsOneWidget);
    expect(find.text('isiZulu'), findsOneWidget);
  });

  testWidgets('search matches the ENGLISH name too', (tester) async {
    // Someone whose keyboard is English must be able to find 한국어 by
    // typing "Korean" — that is what Language.name is carried for.
    await tester.pumpWidget(_host(initial: const [], onDone: (_) {}));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'korean');
    await tester.pumpAndSettle();

    expect(find.text('한국어'), findsOneWidget);
    expect(find.text('isiZulu'), findsNothing);
  });

  testWidgets('search matches the native name as well', (tester) async {
    await tester.pumpWidget(_host(initial: const [], onDone: (_) {}));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '한국');
    await tester.pumpAndSettle();

    expect(find.text('한국어'), findsOneWidget);
  });

  testWidgets('selecting returns the codes, not the labels', (tester) async {
    List<String>? got;
    await tester.pumpWidget(_host(initial: const [], onDone: (v) => got = v));
    await tester.pumpAndSettle();

    await tester.tap(find.text('한국어'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language_picker_done')));
    await tester.pumpAndSettle();

    expect(got, ['ko']);
  });

  testWidgets('the cap is enforced and the extra tap does not stick',
      (tester) async {
    List<String>? got;
    await tester.pumpWidget(_host(
      initial: const ['en', 'ko'], onDone: (v) => got = v, max: 2,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('isiZulu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language_picker_done')));
    await tester.pumpAndSettle();

    expect(got, ['en', 'ko']);
  });

  testWidgets('an already-selected language can be deselected', (tester) async {
    List<String>? got;
    await tester.pumpWidget(_host(initial: const ['ko'], onDone: (v) => got = v));
    await tester.pumpAndSettle();

    await tester.tap(find.text('한국어'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language_picker_done')));
    await tester.pumpAndSettle();

    expect(got, isEmpty);
  });

  testWidgets('a failed catalogue still shows the bundled fallback',
      (tester) async {
    // The picker is on the registration screen. Empty is not an option.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        languageCatalogProvider.overrideWith((ref) async => kLanguageFallback),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LanguagePickerScreen(
          initialSelection: const [], maxSelection: 3, onDone: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('English'), findsWidgets);
  });

  group('a blank name never crashes the picker', () {
    // GET /languages serves 127+ rows and some carry `"name": ""`. Those
    // parse fine, so no catalogue fallback rescues them -- the row simply
    // threw a RangeError on name[0] while building the A-Z section header,
    // red-screening the exact screen App Review rejected.
    test('the section letter falls back past a blank name', () {
      expect(
        sectionLetterFor(const Language(code: 'aa', name: '', nativeName: '')),
        'A',
      );
      expect(
        sectionLetterFor(
          const Language(code: 'bb', name: '   ', nativeName: '   '),
        ),
        'B',
      );
      expect(sectionLetterFor(Language.fromJson({'code': 'cc'})), 'C');
    });

    test('a language with nothing indexable lands in a catch-all section', () {
      expect(
        sectionLetterFor(const Language(code: '', name: '', nativeName: '')),
        '#',
      );
    });

    testWidgets('blank-named rows render rather than throwing', (tester) async {
      final catalog = [
        Language.fromJson({'code': 'aa', 'name': ''}),
        Language.fromJson({'code': 'bb', 'name': '   '}),
        Language.fromJson({'code': 'cc'}),
        // Not parsed at all -- the picker must survive this too.
        const Language(code: 'dd', name: '', nativeName: ''),
      ];

      await tester.pumpWidget(ProviderScope(
        overrides: [
          languageCatalogProvider.overrideWith((ref) async => catalog),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LanguagePickerScreen(
            initialSelection: const [], maxSelection: 3, onDone: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('aa'), findsOneWidget);
      expect(find.text('dd'), findsNothing,
          reason: 'an unparsed blank row has no label to show, but must not '
              'take the screen down with it');
    });
  });

  group('the A-Z index scrolls to a measured offset', () {
    // The index used to jump to `position-in-rest * 56`, which ignored the
    // Recommended header, its rows, the divider under it, and one header per
    // letter section. Tapping M landed hundreds of pixels short.
    final recommended = [
      const Language(code: 'en', name: 'English', nativeName: 'English'),
      const Language(code: 'ko', name: 'Korean', nativeName: '한국어'),
    ];
    final rest = [
      const Language(code: 'ay', name: 'Aymara', nativeName: 'Aymara'),
      const Language(code: 'bg', name: 'Bulgarian', nativeName: 'Български'),
      const Language(code: 'mt', name: 'Maltese', nativeName: 'Malti'),
      const Language(code: 'mr', name: 'Marathi', nativeName: 'मराठी'),
      const Language(code: 'zu', name: 'Zulu', nativeName: 'isiZulu'),
    ];

    test('the offset for a letter is the sum of everything above its header',
        () {
      final layout =
          LanguagePickerLayout(recommended: recommended, rest: rest);

      final headerIndex = layout.slots.indexWhere((s) => s.letter == 'M');
      expect(headerIndex, greaterThan(0));

      final expected = layout.slots
          .take(headerIndex)
          .fold<double>(0, (sum, slot) => sum + slot.height);

      expect(layout.offsetForLetter('M'), expected);
    });

    test('the first section starts below the whole Recommended block', () {
      final layout =
          LanguagePickerLayout(recommended: recommended, rest: rest);

      final naive = rest.indexWhere((l) => l.name.startsWith('A')) * 56.0;
      expect(layout.offsetForLetter('A'), greaterThan(naive),
          reason: 'the Recommended header, its rows and the divider all sit '
              'above the first letter section');
    });

    test('a letter no language starts is not scrollable to', () {
      final layout =
          LanguagePickerLayout(recommended: recommended, rest: rest);

      expect(layout.hasLetter('Q'), isFalse);
      expect(layout.offsetForLetter('Q'), isNull);
      expect(layout.hasLetter('M'), isTrue);
    });

    test('with no Recommended block the offsets shift up by exactly that block',
        () {
      final withRec =
          LanguagePickerLayout(recommended: recommended, rest: rest);
      final without =
          LanguagePickerLayout(recommended: const [], rest: rest);

      final headerIndex = withRec.slots.indexWhere((s) => s.letter == 'A');
      final block = withRec.slots
          .take(headerIndex)
          .fold<double>(0, (sum, slot) => sum + slot.height);

      expect(without.offsetForLetter('M'),
          withRec.offsetForLetter('M')! - block);
    });
  });
}
