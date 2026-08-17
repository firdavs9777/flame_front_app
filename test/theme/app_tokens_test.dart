import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/theme/app_tokens.dart';
import 'package:flame/theme/app_theme.dart';

// context.onOverlay backs overlay chrome that sits on a dark scrim, a photo,
// or a coloured badge that isn't AppTheme.primaryColor — never on the app's
// own primary surface. It happens to read the same white as context.onPrimary
// today only because AppTheme sets onPrimary: AppColors.white in both
// schemes. If onOverlay were ever implemented as an alias of onPrimary, a
// rebrand of primaryColor's foreground would silently make every carousel
// dot and overlay icon invisible in both themes at once — a regression the
// profile_settings_theme_test lint cannot see, because by then these are
// token references, not literals. This test pins onOverlay to a value that
// does not move when onPrimary does.
void main() {
  Future<Color> readOnOverlay(WidgetTester tester, ThemeData theme) async {
    late Color value;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            value = context.onOverlay;
            return const SizedBox();
          },
        ),
      ),
    );
    return value;
  }

  testWidgets(
    'onOverlay is the same colour under a light and a dark theme',
    (tester) async {
      final light = await readOnOverlay(tester, AppTheme.lightTheme);
      final dark = await readOnOverlay(tester, AppTheme.darkTheme);

      expect(light, dark);
    },
  );

  testWidgets(
    'onOverlay does not simply read colorScheme.onPrimary',
    (tester) async {
      // Deliberately give each scheme an onPrimary that is NOT white, so a
      // future implementation that aliases onOverlay to onPrimary fails here
      // instead of silently passing because both happen to equal white today.
      final customLight = AppTheme.lightTheme.copyWith(
        colorScheme: AppTheme.lightTheme.colorScheme.copyWith(
          onPrimary: Colors.pink,
        ),
      );
      final customDark = AppTheme.darkTheme.copyWith(
        colorScheme: AppTheme.darkTheme.colorScheme.copyWith(
          onPrimary: Colors.green,
        ),
      );

      final overlayUnderCustomLight = await readOnOverlay(tester, customLight);
      final overlayUnderCustomDark = await readOnOverlay(tester, customDark);

      expect(overlayUnderCustomLight, isNot(Colors.pink));
      expect(overlayUnderCustomDark, isNot(Colors.green));
      expect(overlayUnderCustomLight, overlayUnderCustomDark);
      expect(overlayUnderCustomLight, AppColors.white);
    },
  );
}
