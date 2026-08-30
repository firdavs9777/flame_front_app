// The splash used to hold for a flat 2500ms and then show its child whatever
// state the session restore was in. That produced both halves of one
// complaint: a returning user whose session restored in 200ms still waited two
// and a half seconds, and a user whose restore took longer got dropped on the
// welcome screen for a moment before being yanked to the main tabs — because
// AuthStatus.initial is neither authenticated nor profileIncomplete, so the
// router's ternary fell through to "signed out".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/screens/splash/splash_screen.dart';

const _child = Key('after-splash');

Widget _host({required bool ready}) => MaterialApp(
      // The splash renders its tagline from the ARBs.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: SplashScreen(
        ready: ready,
        child: const SizedBox(key: _child),
      ),
    );

void main() {
  testWidgets('it holds while the session is still being restored',
      (tester) async {
    await tester.pumpWidget(_host(ready: false));
    await tester.pump(const Duration(seconds: 3));

    expect(find.byKey(_child), findsNothing,
        reason: 'showing the child here is showing a guess — and the guess '
            'the router makes for AuthStatus.initial is "signed out"');
  });

  testWidgets('a resolved session does not wait the old 2.5 seconds',
      (tester) async {
    await tester.pumpWidget(_host(ready: true));
    expect(find.byKey(_child), findsNothing, reason: 'the brand still shows');

    await tester.pump(const Duration(milliseconds: 800));

    expect(find.byKey(_child), findsOneWidget);
  });

  testWidgets('the brand is not skipped on an instant restore', (tester) async {
    await tester.pumpWidget(_host(ready: true));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(_child), findsNothing,
        reason: 'a logo that flashes past for one frame reads as a glitch');
  });

  testWidgets('a restore that never answers does not strand the user',
      (tester) async {
    await tester.pumpWidget(_host(ready: false));
    await tester.pump(const Duration(seconds: 6));

    expect(find.byKey(_child), findsOneWidget);
  });

  testWidgets('becoming ready mid-wait releases it', (tester) async {
    await tester.pumpWidget(_host(ready: false));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(_child), findsNothing);

    await tester.pumpWidget(_host(ready: true));
    await tester.pump();

    expect(find.byKey(_child), findsOneWidget);
  });
}
