import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/kit/kit.dart';

/// Pumps [child] inside a MaterialApp using [theme] and asserts it builds
/// without throwing.
Future<void> _pumpInTheme(
  WidgetTester tester,
  ThemeData theme,
  Widget child,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  expect(tester.takeException(), isNull);
}

void main() {
  final themes = {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  };

  for (final entry in themes.entries) {
    final label = entry.key;
    final theme = entry.value;

    group('kit renders in $label theme', () {
      testWidgets('AppButton across every variant and size', (tester) async {
        for (final variant in AppButtonVariant.values) {
          for (final size in AppButtonSize.values) {
            await _pumpInTheme(
              tester,
              theme,
              AppButton(
                text: 'Go',
                onPressed: () {},
                variant: variant,
                size: size,
              ),
            );
            expect(find.text('Go'), findsOneWidget);
          }
        }
      });

      testWidgets('AppButton loading state shows a spinner', (tester) async {
        await _pumpInTheme(
          tester,
          theme,
          AppButton(text: 'Go', onPressed: () {}, isLoading: true),
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('AppCard renders its child', (tester) async {
        await _pumpInTheme(
          tester,
          theme,
          const AppCard(child: Text('card body')),
        );
        expect(find.text('card body'), findsOneWidget);
      });

      testWidgets('AppInput renders with a label', (tester) async {
        await _pumpInTheme(
          tester,
          theme,
          const AppInput(label: 'Email', hint: 'you@example.com'),
        );
        expect(find.text('Email'), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);
      });

      testWidgets('AppAvatar renders initials when no image', (tester) async {
        await _pumpInTheme(
          tester,
          theme,
          const AppAvatar(name: 'Ada Lovelace'),
        );
        // First-letter initial shows for a name-only avatar.
        expect(find.textContaining('A'), findsOneWidget);
      });

      testWidgets('AppBadge renders its label', (tester) async {
        await _pumpInTheme(
          tester,
          theme,
          const AppBadge(text: 'NEW'),
        );
        expect(find.text('NEW'), findsOneWidget);
      });

      testWidgets('AppDotBadge shows a count over its child', (tester) async {
        await _pumpInTheme(
          tester,
          theme,
          const AppDotBadge(count: 5, child: Icon(Icons.chat_bubble)),
        );
        expect(find.text('5'), findsOneWidget);
        expect(find.byIcon(Icons.chat_bubble), findsOneWidget);
      });

      testWidgets('AppLoading renders a progress indicator', (tester) async {
        await _pumpInTheme(tester, theme, const AppLoading());
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });
    });
  }
}
