import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/config/env.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/screens/main_shell.dart';
import 'package:flame/screens/settings/settings_screen.dart';

Widget _app({int? navIndex}) => ProviderScope(
      overrides: [
        if (navIndex != null) bottomNavIndexProvider.overrideWith((ref) => navIndex),
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
        home: const MainShell(),
      ),
    );

void main() {
  testWidgets('Settings is not a tab', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Settings'), findsNothing,
        reason: 'a destination visited rarely does not belong beside Discover');
  });

  testWidgets('the bar carries Discover and Profile, plus Chat when enabled',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    if (EnvConfig.current.chatEnabled) {
      expect(find.text('Chat'), findsOneWidget);
    }
  });

  testWidgets('a stale nav index beyond the tab count does not throw',
      (tester) async {
    // bottomNavIndexProvider holds a raw int that outlives a release. Removing an
    // IndexedStack child makes an old value point past the end.
    await tester.pumpWidget(_app(navIndex: 9));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('SettingsScreen is not built by the shell', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.byType(SettingsScreen), findsNothing);
  });
}
