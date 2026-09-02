import 'dart:async';

import 'package:flame/screens/settings/widgets/settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/providers/notification_settings_provider.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/push/push_permission.dart';
import 'package:flame/providers/push_provider.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends ConsumerState<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  bool _initialized = false;

  /// What the OS will actually do, as distinct from what the switches want.
  PushPermissionStatus _permission = PushPermissionStatus.unknown;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        ref.read(notificationSettingsProvider.notifier).load();
        _refreshPermission();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The only way back from a denied permission is the system settings app,
  /// which means leaving Flame and returning. Re-reading on resume is what
  /// makes the banner disappear on the way back instead of on the next launch.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final status = await ref.read(pushPermissionProvider).status();
    if (!mounted) return;

    final wasBlocked = pushIsBlocked(_permission);
    setState(() => _permission = status);

    // Granted while we were away. Without this the device stays unregistered
    // until the next launch, and the user — who just turned notifications on —
    // concludes it does not work.
    if (wasBlocked && status == PushPermissionStatus.authorized) {
      unawaited(ref.read(pushServiceProvider).registerDevice());
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationSettingsProvider);

    // What the OS says overrides what the switches want. When push is blocked
    // every push control is inert, so none of them are offered as if they
    // worked -- the rule env.dart states: a control promising something the
    // app cannot do is worse than no control.
    final blocked = pushIsBlocked(_permission);

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
          // A push switch is live only when the OS allows notifications AND
          // the master switch is on. The master itself needs only the former.
          ValueChanged<bool>? push(Future<bool> Function(bool) apply) {
            if (blocked || !settings.enabled) return null;
            return (value) => _apply(context, () => apply(value));
          }

          final notifier = ref.read(notificationSettingsProvider.notifier);

          return ListView(
            children: [
              if (blocked) _PushBlockedBanner(onOpenSettings: _openSettings),

              // Two sections, because the two channels obey different rules:
              // the master switch below governs push and NOT email. Without a
              // visible split, a disabled "Chat messages" next to an enabled
              // "Promotions" just looks like a bug.
              SettingsSection(
                title: context.l10n.notifSectionPush,
                children: [
                  _switch(
                    context,
                    key: 'notif_all',
                    title: context.l10n.notifAll,
                    subtitle: context.l10n.notifAllSubtitle,
                    value: settings.enabled,
                    onChanged: blocked
                        ? null
                        : (value) =>
                            _apply(context, () => notifier.setEnabled(value)),
                  ),
                  const Divider(height: 1),
                  _switch(
                    context,
                    key: 'notif_chat_messages',
                    title: context.l10n.notifMessages,
                    subtitle: context.l10n.notifMessagesSubtitle,
                    value: settings.chatMessages,
                    onChanged: push(notifier.setChatMessages),
                  ),
                  _switch(
                    context,
                    key: 'notif_matches',
                    title: context.l10n.notifNewMatches,
                    subtitle: context.l10n.notifNewMatchesSubtitle,
                    value: settings.matches,
                    onChanged: push(notifier.setMatches),
                  ),
                  _switch(
                    context,
                    key: 'notif_reminders_push',
                    title: context.l10n.notifRemindersPush,
                    subtitle: context.l10n.notifRemindersPushSubtitle,
                    value: settings.reengagementPush,
                    onChanged: push(notifier.setReengagementPush),
                  ),
                  _switch(
                    context,
                    key: 'notif_promotions_push',
                    title: context.l10n.notifPromotionsPush,
                    subtitle: context.l10n.notifPromotionsPushSubtitle,
                    value: settings.promotionsPush,
                    onChanged: push(notifier.setPromotionsPush),
                  ),
                ],
              ),
              SettingsSection(
                title: context.l10n.notifSectionEmail,
                children: [
                  // NOT gated on settings.enabled, and NOT on `blocked`
                  // either. Both concern push; email arrives regardless of
                  // what the OS allows on this device, and disabling these
                  // would repeat the same mistake pointing the other way.
                  _switch(
                    context,
                    key: 'notif_reminders_email',
                    title: context.l10n.notifReminders,
                    subtitle: context.l10n.notifRemindersSubtitle,
                    value: settings.reengagement,
                    onChanged: (value) =>
                        _apply(context, () => notifier.setReengagement(value)),
                  ),
                  const Divider(height: 1),
                  _switch(
                    context,
                    key: 'notif_promotions_email',
                    title: context.l10n.notifPromotions,
                    subtitle: context.l10n.notifPromotionsSubtitle,
                    value: settings.promotions,
                    onChanged: (value) =>
                        _apply(context, () => notifier.setPromotions(value)),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _switch(
    BuildContext context, {
    required String key,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile(
      // Keyed because "Promotions" and "Reminders" each appear twice — once
      // per channel. The section header tells them apart on screen; a key
      // tells them apart everywhere else.
      key: Key(key),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      activeThumbColor: AppTheme.primaryColor,
      onChanged: onChanged,
    );
  }

  /// Runs a settings mutation and reports failure.
  ///
  /// One helper rather than a method per switch: the seven were identical
  /// apart from which setter they called, which is exactly the shape that
  /// grows an eighth with a subtly different error path.
  Future<void> _apply(
    BuildContext context,
    Future<bool> Function() request,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await request();
    if (!context.mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.notifUpdateFailed)),
      );
    }
  }

  Future<void> _openSettings() async {
    await ref.read(pushPermissionProvider).openSystemSettings();
    // No refresh here: returning from system settings raises a resume, and
    // didChangeAppLifecycleState re-reads there. Refreshing now would read the
    // old value, because the user has not changed anything yet.
  }
}

/// Shown when the operating system will not display notifications.
///
/// Deliberately not dismissible: it is not an announcement, it is the reason
/// every switch below it is greyed out.
class _PushBlockedBanner extends StatelessWidget {
  const _PushBlockedBanner({required this.onOpenSettings});

  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_off_outlined,
                  color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.notifBlockedTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.notifBlockedBody,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              key: const Key('notif_open_system_settings'),
              onPressed: onOpenSettings,
              child: Text(context.l10n.notifOpenSettings),
            ),
          ),
        ],
      ),
    );
  }
}
