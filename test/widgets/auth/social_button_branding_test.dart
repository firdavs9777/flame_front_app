import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/auth/social_sign_in_buttons.dart';

Widget _host(Widget home) => ProviderScope(
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
    home: home,
  ),
);

void main() {
  testWidgets('each provider renders its official SVG brand mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Scaffold(
          body: SocialSignInButtons(
            visibilityOverride: SocialProviderVisibility(
              google: true,
              apple: true,
              facebook: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsNWidgets(3));
  });

  testWidgets('brand marks are not Material font-icon stand-ins', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Scaffold(
          body: SocialSignInButtons(
            visibilityOverride: SocialProviderVisibility(
              google: true,
              apple: true,
              facebook: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Regression guard: Icons.g_mobiledata_rounded / facebook_rounded /
    // apple_rounded are lookalikes, not the licensed marks, and violate the
    // providers' branding guidelines.
    for (final icon in [
      Icons.g_mobiledata_rounded,
      Icons.facebook_rounded,
      Icons.apple_rounded,
    ]) {
      expect(find.byIcon(icon), findsNothing, reason: '$icon must not be used');
    }
  });

  testWidgets('only the visible provider contributes a brand mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const Scaffold(
          body: SocialSignInButtons(
            visibilityOverride: SocialProviderVisibility(google: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsOneWidget);
  });
}
