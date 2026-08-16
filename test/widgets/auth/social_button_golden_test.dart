import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/auth/social_sign_in_buttons.dart';

/// Golden for the brand marks. These are trademarked assets rendered from
/// hand-authored SVG path data, so a pixel diff is the only thing that catches
/// a malformed path — a widget test can only prove an SvgPicture exists.
void main() {
  testWidgets('social buttons render their brand marks (light)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: kSupportedLocales,
          theme: AppTheme.lightTheme,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(
            backgroundColor: Color(0xFFEEEEEE),
            body: Padding(
              padding: EdgeInsets.all(24),
              child: SocialSignInButtons(
                visibilityOverride: SocialProviderVisibility(
                  google: true,
                  apple: true,
                  facebook: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SocialSignInButtons),
      matchesGoldenFile('goldens/social_buttons_light.png'),
    );
  });
}
