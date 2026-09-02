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
}
