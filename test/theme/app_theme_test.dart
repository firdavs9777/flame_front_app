import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/theme/app_theme.dart';

void main() {
  group('AppTheme', () {
    test('light theme is light, dark theme is dark', () {
      expect(AppTheme.lightTheme.brightness, Brightness.light);
      expect(AppTheme.darkTheme.brightness, Brightness.dark);
    });

    test('both themes use Material 3 and the coral primary', () {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        expect(theme.useMaterial3, isTrue);
        expect(theme.colorScheme.primary, AppColors.primary);
      }
    });

    test('dark theme reaches parity with light on component themes', () {
      // The whole point of Phase A: the dark theme previously omitted these.
      final dark = AppTheme.darkTheme;
      expect(dark.elevatedButtonTheme.style, isNotNull);
      expect(dark.outlinedButtonTheme.style, isNotNull);
      expect(dark.textButtonTheme.style, isNotNull);
      expect(dark.inputDecorationTheme.filled, isTrue);
      expect(dark.textTheme.bodyLarge, isNotNull);
      expect(dark.textTheme.titleLarge, isNotNull);
    });

    test('legacy flat color API is preserved for existing call sites', () {
      expect(AppTheme.primaryColor, AppColors.primary);
      expect(AppTheme.errorColor, AppColors.error);
      expect(AppTheme.successColor, AppColors.success);
      expect(AppTheme.textPrimary, isA<Color>());
      expect(AppTheme.secondaryColor, AppColors.secondary);
    });
  });
}
