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
  _chatTokenResolution();
  Future<Map<String, Color>> readTokens(
    WidgetTester tester,
    ThemeData theme,
  ) async {
    late Map<String, Color> values;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            values = {
              'surface': context.surface,
              'onSurface': context.onSurface,
              'secondaryText': context.secondaryText,
              'fill': context.fill,
            };
            return const SizedBox();
          },
        ),
      ),
    );
    return values;
  }

  // A token that silently resolves to the same colour as another token is
  // invisible to profile_settings_theme_test, which only bans `Colors.*`
  // literals — the code reads `context.fill`, looks correct, and renders
  // nothing.
  //
  // Both of these collapsed because `AppTokens` reads two ColorScheme roles
  // (`surfaceContainerHighest`, `onSurfaceVariant`) that `AppTheme` never
  // passed to `ColorScheme.light()` / `ColorScheme.dark()`, and the SDK
  // getters fall back to `surface` / `onSurface` respectively. The cost was
  // real: `fill == surface` removed the only delineation the edit-profile
  // form's fields had, because `inputDecorationTheme.enabledBorder` is
  // `BorderSide.none` in both themes.
  group('semantic tokens stay distinct from the ones they sit on', () {
    final themes = {'light': AppTheme.lightTheme, 'dark': AppTheme.darkTheme};

    for (final entry in themes.entries) {
      testWidgets('in ${entry.key} theme', (tester) async {
        final tokens = await readTokens(tester, entry.value);

        expect(
          tokens['fill'],
          isNot(tokens['surface']),
          reason:
              'fill is an input fill drawn INSIDE a surface-coloured card, '
              'and with enabledBorder: BorderSide.none it is the only thing '
              'marking the field boundary. Equal to surface, every text '
              'field on the edit-profile form renders as bare text.',
        );
        expect(
          tokens['secondaryText'],
          isNot(tokens['onSurface']),
          reason:
              'secondaryText is documented as "present but not the point"; '
              'equal to onSurface, every caption, hint and section header '
              'prints at full body strength and the hierarchy flattens.',
        );
      });
    }
  });

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

// Appended by the chat sweep. The literal-banning gate cannot see a token that
// resolves to the wrong colour — which is exactly how `context.fill` shipped
// equal to `context.surface` and made six edit-profile fields invisible. These
// pin the inequalities the chat surface now depends on.
void _chatTokenResolution() {
  test('chat tokens resolve to distinguishable colours in both themes', () {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final scheme = theme.colorScheme;
      final label = theme.brightness.name;

      expect(scheme.surfaceContainerHighest, isNot(scheme.surface),
          reason: 'an incoming bubble sits on the page: fill must differ from '
              'surface ($label)');
      expect(scheme.onSurfaceVariant, isNot(scheme.onSurface),
          reason: 'a timestamp must read as quieter than the message ($label)');
      expect(theme.dividerTheme.color, isNot(scheme.surfaceContainerHighest),
          reason: 'a reply-quote rule is drawn on a fill, so a divider equal to '
              'fill is invisible ($label)');
      expect(scheme.onPrimary, isNot(AppColors.readReceipt),
          reason: 'a read tick must be tellable from a delivered one ($label)');
    }
  });
}
