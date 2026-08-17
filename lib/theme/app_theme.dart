import 'package:flutter/material.dart';

/// Flame Design System
///
/// A token-based theme (colors, typography, spacing, radius, shadows) plus
/// light/dark [ThemeData]. Ported from the BananaTalk design system and
/// recolored to Flame's coral/fire identity.
///
/// Font: system font (San Francisco on iOS, Roboto on Android) — built-in
/// support for CJK and every shipped locale, no font loading.

// ============================================================================
// COLORS
// ============================================================================

class AppColors {
  AppColors._();

  // Brand — coral / flame
  static const Color primary = Color(0xFFFF6B6B);
  static const Color primaryLight = Color(0xFFFFB0B0);
  static const Color primaryDark = Color(0xFFE05252);

  static const Color secondary = Color(0xFFFF8E8E);
  static const Color secondaryLight = Color(0xFFFFC2C2);
  static const Color secondaryDark = Color(0xFFCC6E6E);

  static const Color accent = Color(0xFFFFE66D);
  static const Color accentLight = Color(0xFFFFF3AE);
  static const Color accentDark = Color(0xFFCCB857);

  // Semantic
  static const Color success = Color(0xFF2ECC71);
  static const Color successLight = Color(0xFFE9F9EF);
  static const Color warning = Color(0xFFFF9800);
  static const Color warningLight = Color(0xFFFFF3E0);
  static const Color error = Color(0xFFE74C3C);
  static const Color errorLight = Color(0xFFFDECEA);
  static const Color info = Color(0xFF2196F3);
  static const Color infoLight = Color(0xFFE3F2FD);

  // Neutrals
  static const Color black = Color(0xFF000000);
  static const Color gray900 = Color(0xFF2C3E50);
  static const Color gray800 = Color(0xFF34495E);
  static const Color gray700 = Color(0xFF5D6D7E);
  static const Color gray600 = Color(0xFF7F8C8D);
  static const Color gray500 = Color(0xFF95A5A6);
  static const Color gray400 = Color(0xFFBDC3C7);
  static const Color gray300 = Color(0xFFD5DBDB);
  static const Color gray200 = Color(0xFFECF0F1);
  static const Color gray100 = Color(0xFFF4F6F7);
  static const Color gray50 = Color(0xFFFAFAFA);
  static const Color white = Color(0xFFFFFFFF);

  // Backgrounds / surfaces
  static const Color backgroundLight = Color(0xFFFAFAFA);
  static const Color backgroundDark = Color(0xFF1A1A2E);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF16213E);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF16213E);

  // Online status
  static const Color online = Color(0xFF2ECC71);
  static const Color offline = Color(0xFF95A5A6);
  static const Color away = Color(0xFFFF9800);
  static const Color busy = Color(0xFFE74C3C);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warmGradient = LinearGradient(
    colors: [primary, accent],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

// ============================================================================
// SPACING
// ============================================================================

class AppSpacing {
  AppSpacing._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;
  static const double massive = 64;

  static const EdgeInsets paddingXS = EdgeInsets.all(xs);
  static const EdgeInsets paddingSM = EdgeInsets.all(sm);
  static const EdgeInsets paddingMD = EdgeInsets.all(md);
  static const EdgeInsets paddingLG = EdgeInsets.all(lg);
  static const EdgeInsets paddingXL = EdgeInsets.all(xl);
  static const EdgeInsets paddingXXL = EdgeInsets.all(xxl);

  static const EdgeInsets paddingHorizontalSM = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets paddingHorizontalMD = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets paddingHorizontalLG = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets paddingHorizontalXL = EdgeInsets.symmetric(horizontal: xl);

  static const EdgeInsets paddingVerticalSM = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets paddingVerticalMD = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets paddingVerticalLG = EdgeInsets.symmetric(vertical: lg);

  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: lg, vertical: md);
  static const EdgeInsets cardPadding = EdgeInsets.all(lg);
}

// ============================================================================
// BORDER RADIUS
// ============================================================================

class AppRadius {
  AppRadius._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double round = 999;

  static final BorderRadius borderXS = BorderRadius.circular(xs);
  static final BorderRadius borderSM = BorderRadius.circular(sm);
  static final BorderRadius borderMD = BorderRadius.circular(md);
  static final BorderRadius borderLG = BorderRadius.circular(lg);
  static final BorderRadius borderXL = BorderRadius.circular(xl);
  static final BorderRadius borderXXL = BorderRadius.circular(xxl);
  static final BorderRadius borderRound = BorderRadius.circular(round);
}

// ============================================================================
// SHADOWS
// ============================================================================

class AppShadows {
  AppShadows._();

  static List<BoxShadow> get none => [];

  static List<BoxShadow> get sm => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get md => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get lg => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get xl => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get colored => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.3),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];
}

// ============================================================================
// TYPOGRAPHY
// ============================================================================

class AppTypography {
  AppTypography._();

  static const TextStyle displayLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
    height: 1.2,
  );
  static const TextStyle displayMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.25,
    height: 1.25,
  );
  static const TextStyle displaySmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    letterSpacing: 0,
    height: 1.3,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );
  static const TextStyle headlineMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );
  static const TextStyle headlineSmall = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.4,
  );
  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.45,
  );
  static const TextStyle titleSmall = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.45,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.normal,
    letterSpacing: -0.2,
    height: 1.5,
  );
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.normal,
    letterSpacing: -0.1,
    height: 1.5,
  );
  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.normal,
    height: 1.45,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.4,
  );
  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.35,
  );
  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.3,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    height: 1.35,
    color: AppColors.gray600,
  );

  static const TextStyle buttonLarge = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );
  static const TextStyle buttonMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );
  static const TextStyle buttonSmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );
}

// ============================================================================
// THEME DATA
// ============================================================================

class AppTheme {
  AppTheme._();

  // ---- Legacy flat color API (kept for existing call sites) ---------------
  static const Color primaryColor = AppColors.primary;
  static const Color secondaryColor = AppColors.secondary;
  static const Color accentColor = AppColors.accent;
  static const Color backgroundColor = AppColors.backgroundLight;
  static const Color surfaceColor = AppColors.surfaceLight;
  static const Color errorColor = AppColors.error;
  static const Color successColor = AppColors.success;
  static const Color textPrimary = AppColors.gray900;
  static const Color textSecondary = AppColors.gray600;
  static const Color dividerColor = AppColors.gray200;

  static TextTheme _textTheme(Color primary, Color secondary, Color tertiary) {
    return TextTheme(
      displayLarge: AppTypography.displayLarge.copyWith(color: primary),
      displayMedium: AppTypography.displayMedium.copyWith(color: primary),
      displaySmall: AppTypography.displaySmall.copyWith(color: primary),
      headlineLarge: AppTypography.headlineLarge.copyWith(color: primary),
      headlineMedium: AppTypography.headlineMedium.copyWith(color: primary),
      headlineSmall: AppTypography.headlineSmall.copyWith(color: primary),
      titleLarge: AppTypography.titleLarge.copyWith(color: primary),
      titleMedium: AppTypography.titleMedium.copyWith(color: primary),
      titleSmall: AppTypography.titleSmall.copyWith(color: secondary),
      bodyLarge: AppTypography.bodyLarge.copyWith(color: primary),
      bodyMedium: AppTypography.bodyMedium.copyWith(color: secondary),
      bodySmall: AppTypography.bodySmall.copyWith(color: tertiary),
      labelLarge: AppTypography.labelLarge.copyWith(color: primary),
      labelMedium: AppTypography.labelMedium.copyWith(color: secondary),
      labelSmall: AppTypography.labelSmall.copyWith(color: tertiary),
    );
  }

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.backgroundLight,
        textTheme: _textTheme(AppColors.gray900, AppColors.gray800, AppColors.gray700),
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          primaryContainer: AppColors.primaryLight,
          secondary: AppColors.secondary,
          secondaryContainer: AppColors.secondaryLight,
          tertiary: AppColors.accent,
          surface: AppColors.surfaceLight,
          // Both of these are read by AppTokens (`context.fill`,
          // `context.secondaryText`) and MUST be passed explicitly: the SDK
          // getters are `_surfaceContainerHighest ?? surface` and
          // `_onSurfaceVariant ?? onSurface`, so omitting them does not
          // produce a derived shade — it silently collapses each token onto
          // the one it is supposed to sit on. `fill` in particular is the only
          // thing delineating a text field, because `inputDecorationTheme`
          // below sets `enabledBorder: BorderSide.none`. The values match that
          // same `inputDecorationTheme.fillColor` / `AppTheme.textSecondary`
          // so the tokens agree with the widget themes rather than inventing a
          // second palette. Pinned by test/theme/app_tokens_test.dart.
          surfaceContainerHighest: AppColors.gray100,
          error: AppColors.error,
          onPrimary: AppColors.white,
          onSecondary: AppColors.gray900,
          onSurface: AppColors.gray900,
          onSurfaceVariant: AppColors.gray600,
          onError: AppColors.white,
          outline: AppColors.gray300,
          outlineVariant: AppColors.gray200,
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: AppColors.surfaceLight,
          foregroundColor: AppColors.gray900,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: AppTypography.titleLarge.copyWith(color: AppColors.gray900),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: AppColors.cardLight,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderLG),
          margin: EdgeInsets.zero,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.white,
            disabledBackgroundColor: AppColors.gray300,
            disabledForegroundColor: AppColors.gray500,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRound),
            textStyle: AppTypography.buttonMedium,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRound),
            textStyle: AppTypography.buttonMedium,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            textStyle: AppTypography.buttonMedium,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.gray100,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(borderRadius: AppRadius.borderMD, borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: AppRadius.borderMD, borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.borderMD,
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: AppRadius.borderMD,
            borderSide: const BorderSide(color: AppColors.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: AppRadius.borderMD,
            borderSide: const BorderSide(color: AppColors.error, width: 2),
          ),
          hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.gray500),
          labelStyle: AppTypography.labelLarge.copyWith(color: AppColors.gray700),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.gray100,
          selectedColor: AppColors.primaryLight,
          labelStyle: AppTypography.labelMedium,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRound),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.gray200, thickness: 1, space: 1),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.surfaceLight,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.gray500,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 4,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.gray900,
          contentTextStyle: AppTypography.bodyMedium.copyWith(color: AppColors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMD),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.white,
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderXL),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.white,
          modalBackgroundColor: AppColors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.backgroundDark,
        textTheme: _textTheme(AppColors.gray100, AppColors.gray200, AppColors.gray300),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          primaryContainer: AppColors.primaryDark,
          secondary: AppColors.secondary,
          secondaryContainer: AppColors.secondaryDark,
          tertiary: AppColors.accent,
          surface: AppColors.surfaceDark,
          // See the light scheme above: these two are not optional. Values
          // match this theme's own `inputDecorationTheme.fillColor` (gray800)
          // and `labelStyle` (gray400).
          surfaceContainerHighest: AppColors.gray800,
          error: AppColors.error,
          onPrimary: AppColors.white,
          onSecondary: AppColors.gray900,
          onSurface: AppColors.gray100,
          onSurfaceVariant: AppColors.gray400,
          onError: AppColors.white,
          outline: AppColors.gray700,
          outlineVariant: AppColors.gray800,
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: AppColors.surfaceDark,
          foregroundColor: AppColors.gray100,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: AppTypography.titleLarge.copyWith(color: AppColors.gray100),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: AppColors.cardDark,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderLG),
          margin: EdgeInsets.zero,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.white,
            disabledBackgroundColor: AppColors.gray800,
            disabledForegroundColor: AppColors.gray600,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRound),
            textStyle: AppTypography.buttonMedium,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRound),
            textStyle: AppTypography.buttonMedium,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            textStyle: AppTypography.buttonMedium,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.gray800,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(borderRadius: AppRadius.borderMD, borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: AppRadius.borderMD, borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.borderMD,
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: AppRadius.borderMD,
            borderSide: const BorderSide(color: AppColors.error, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: AppRadius.borderMD,
            borderSide: const BorderSide(color: AppColors.error, width: 2),
          ),
          hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.gray500),
          labelStyle: AppTypography.labelLarge.copyWith(color: AppColors.gray400),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.gray800,
          selectedColor: AppColors.primaryDark,
          labelStyle: AppTypography.labelMedium.copyWith(color: AppColors.gray100),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRound),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.gray800, thickness: 1, space: 1),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.surfaceDark,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.gray500,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 4,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.gray800,
          contentTextStyle: AppTypography.bodyMedium.copyWith(color: AppColors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderMD),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.cardDark,
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderXL),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.surfaceDark,
          modalBackgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
        ),
      );
}
