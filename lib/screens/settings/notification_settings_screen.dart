import 'package:flame/screens/settings/widgets/settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/providers/notification_settings_provider.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/core/i18n/build_context_ext.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        ref.read(notificationSettingsProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.notifTitle)),
      body: state.when(
        loading: () => const Center(child: AppLoading()),
        error: (error, stack) => AppErrorState(
          title: context.l10n.notifLoadFailed,
          message: '$error',
          onRetry: () =>
              ref.read(notificationSettingsProvider.notifier).load(),
        ),
        data: (settings) {
          return ListView(
            children: [
              // Two sections, because the two channels obey different rules:
              // the master switch below governs push and NOT email. Without a
              // visible split, a disabled "Chat messages" next to an enabled
              // "Promotions" just looks like a bug.
              SettingsSection(
                title: context.l10n.notifSectionPush,
                children: [
                  SwitchListTile(
                    title: Text(context.l10n.notifAll),
                    subtitle: Text(context.l10n.notifAllSubtitle),
                    value: settings.enabled,
                    activeThumbColor: AppTheme.primaryColor,
                    onChanged: (value) => _setEnabled(context, value),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(context.l10n.notifMessages),
                    subtitle: Text(context.l10n.notifMessagesSubtitle),
                    value: settings.chatMessages,
                    activeThumbColor: AppTheme.primaryColor,
                    onChanged: settings.enabled
                        ? (value) => _setChatMessages(context, value)
                        : null,
                  ),
                  SwitchListTile(
                    title: Text(context.l10n.notifNewMatches),
                    subtitle: Text(context.l10n.notifNewMatchesSubtitle),
                    value: settings.matches,
                    activeThumbColor: AppTheme.primaryColor,
                    onChanged: settings.enabled
                        ? (value) => _setMatches(context, value)
                        : null,
                  ),
                ],
              ),
              SettingsSection(
                title: context.l10n.notifSectionEmail,
                children: [
                  // NOT gated on settings.enabled. That switch is about push;
                  // silently stopping someone's email from it would be wrong.
                  SwitchListTile(
                    title: Text(context.l10n.notifReminders),
                    subtitle: Text(context.l10n.notifRemindersSubtitle),
                    value: settings.reengagement,
                    activeThumbColor: AppTheme.primaryColor,
                    onChanged: (value) => _setReengagement(context, value),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(context.l10n.notifPromotions),
                    subtitle: Text(context.l10n.notifPromotionsSubtitle),
                    value: settings.promotions,
                    activeThumbColor: AppTheme.primaryColor,
                    onChanged: (value) => _setPromotions(context, value),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _setEnabled(BuildContext context, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok =
        await ref.read(notificationSettingsProvider.notifier).setEnabled(value);
    if (!context.mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.notifUpdateFailed)),
      );
    }
  }

  Future<void> _setChatMessages(BuildContext context, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(notificationSettingsProvider.notifier)
        .setChatMessages(value);
    if (!context.mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.notifUpdateFailed)),
      );
    }
  }

  Future<void> _setMatches(BuildContext context, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok =
        await ref.read(notificationSettingsProvider.notifier).setMatches(value);
    if (!context.mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.notifUpdateFailed)),
      );
    }
  }

  Future<void> _setReengagement(BuildContext context, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(notificationSettingsProvider.notifier)
        .setReengagement(value);
    if (!context.mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.notifUpdateFailed)),
      );
    }
  }

  Future<void> _setPromotions(BuildContext context, bool value) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(notificationSettingsProvider.notifier)
        .setPromotions(value);
    if (!context.mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.notifUpdateFailed)),
      );
    }
  }
}
