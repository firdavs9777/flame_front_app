import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'theme/app_theme.dart';
import 'providers/providers.dart';
import 'screens/main_shell.dart';
import 'screens/discover/discover_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/auth/registration/social_profile_completion_flow.dart';
import 'screens/splash/splash_screen.dart';
import 'core/i18n/locale_provider.dart';
import 'core/i18n/supported_locales.dart';
import 'core/i18n/error_strings_for.dart';
import 'l10n/gen/app_localizations.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final container = ProviderContainer();
  await container.read(localeProvider.notifier).initialize(
    deviceLocales: WidgetsBinding.instance.platformDispatcher.locales.toList(),
  );
  runApp(UncontrolledProviderScope(container: container, child: const FlameApp()));
}

Locale? _parseLocaleTag(String tag) {
  final parts = tag.split('-');
  if (parts.isEmpty) return null;
  if (parts.length == 1) return Locale(parts[0]);
  if (parts.length == 2) return Locale(parts[0], parts[1]);
  return null;
}

class FlameApp extends ConsumerWidget {
  const FlameApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final authState = ref.watch(authProvider);
    final locale = ref.watch(localeProvider);

    ref.listen<AuthState>(authProvider, (previous, next) {
      final user = next.user;
      if (user == null || user.preferredLanguage == null) return;
      final desired = _parseLocaleTag(user.preferredLanguage!);
      if (desired == null) return;
      final current = ref.read(localeProvider);
      if (current == desired) return;
      // Backend wins on launch (user may have changed language on another device).
      ref.read(localeProvider.notifier).setLocale(desired);
    });

    return MaterialApp(
      title: 'Flame',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      locale: locale,
      supportedLocales: kSupportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        ErrorStringsFor.prime(AppLocalizations.of(context));
        return child!;
      },
      home: SplashScreen(
        child: authState.isAuthenticated
            ? const MainShell()
            : authState.isProfileIncomplete
                ? const SocialProfileCompletionFlow()
                : const WelcomeScreen(),
      ),
      routes: {
        '/discover': (context) => const DiscoverScreen(),
      },
    );
  }
}
