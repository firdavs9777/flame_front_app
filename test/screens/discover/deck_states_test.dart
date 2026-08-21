import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/screens/discover/widgets/deck_states.dart';

var actions = 0;

Future<void> pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1.0,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    supportedLocales: kSupportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => actions = 0);

  testWidgets('filters-empty names the cause and offers a way out',
      (tester) async {
    await pump(tester, DeckEmptyForFilters(onRelaxFilters: () => actions++));

    expect(find.text('No one matches these filters'), findsOneWidget);
    await tester.tap(find.text('Relax filters'));
    expect(actions, 1);
  });

  testWidgets('seen-everyone offers only a refresh', (tester) async {
    await pump(tester, DeckSeenEveryone(onRefresh: () => actions++));

    expect(find.text("You've seen everyone nearby"), findsOneWidget);
    // Nothing the user changes conjures more people, so there is no
    // "relax filters" here.
    expect(find.text('Relax filters'), findsNothing);
    await tester.tap(find.text('Refresh'));
    expect(actions, 1);
  });

  testWidgets('an error shows the reason and never the other two states',
      (tester) async {
    await pump(tester, DeckError(error: 'offline', onRetry: () => actions++));

    expect(find.text("Couldn't load profiles"), findsOneWidget);
    expect(find.text('offline'), findsOneWidget);
    expect(find.text('No one matches these filters'), findsNothing);
    expect(find.text("You've seen everyone nearby"), findsNothing);
    await tester.tap(find.text('Retry'));
    expect(actions, 1);
  });

  testWidgets('all three survive 2x text scale without overflow',
      (tester) async {
    for (final widget in [
      DeckEmptyForFilters(onRelaxFilters: () {}),
      DeckSeenEveryone(onRefresh: () {}),
      const DeckError(error: 'a rather long error message here', onRetry: _noop),
    ]) {
      await pump(tester, widget, textScale: 2.0);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('they render on a tablet too', (tester) async {
    await pump(tester, DeckSeenEveryone(onRefresh: () {}),
        size: const Size(1024, 1366));

    expect(tester.takeException(), isNull);
    expect(find.text("You've seen everyone nearby"), findsOneWidget);
  });
}

void _noop() {}
