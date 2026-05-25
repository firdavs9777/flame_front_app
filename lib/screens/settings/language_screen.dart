import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/i18n/locale_provider.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/providers/auth_provider.dart';
import 'package:flame/services/auth_service.dart';

class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.languagePickerTitle)),
      body: ListView(
        children: [
          for (final locale in kSupportedLocales)
            RadioListTile<Locale>(
              value: locale,
              groupValue: current,
              onChanged: (picked) => _select(context, ref, picked),
              title: Text(displayNameOf(locale)),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.phone_iphone),
            title: Text(context.l10n.languageUseDevice),
            onTap: () => _useDevice(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _select(BuildContext context, WidgetRef ref, Locale? picked) async {
    if (picked == null) return;
    await ref.read(localeProvider.notifier).setLocale(picked);
    _syncBackend(ref, picked.toLanguageTag());
  }

  Future<void> _useDevice(BuildContext context, WidgetRef ref) async {
    await ref.read(localeProvider.notifier).clearLocale(
      deviceLocales: WidgetsBinding.instance.platformDispatcher.locales,
    );
    final resolved = ref.read(localeProvider);
    if (resolved != null) {
      _syncBackend(ref, resolved.toLanguageTag());
    }
  }

  void _syncBackend(WidgetRef ref, String tag) {
    if (!ref.read(authProvider).isAuthenticated) return;
    unawaited(
      AuthService().updatePreferredLanguage(tag).then((_) {}, onError: (e) {
        debugPrint('preferred_language sync failed: $e');
      }),
    );
  }
}
