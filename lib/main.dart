import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'theme/app_theme.dart';
import 'providers/providers.dart';
import 'screens/main_shell.dart';
import 'screens/discover/discover_screen.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/splash/splash_screen.dart';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ProviderScope(child: FlameApp()));
}

class FlameApp extends ConsumerWidget {
  const FlameApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final authState = ref.watch(authProvider);

    return MaterialApp(
      title: 'Flame',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: SplashScreen(
        child: authState.isAuthenticated ? const MainShell() : const WelcomeScreen(),
      ),
      routes: {
        '/discover': (context) => const DiscoverScreen(),
      },
    );
  }
}
