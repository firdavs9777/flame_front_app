import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/providers/notification_settings_provider.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/kit/kit.dart';

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
      appBar: AppBar(title: const Text('Notifications')),
      body: state.when(
        loading: () => const Center(child: AppLoading()),
        error: (error, stack) => AppErrorState(
          title: 'Could not load notification settings',
          message: '$error',
          onRetry: () =>
              ref.read(notificationSettingsProvider.notifier).load(),
        ),
        data: (settings) {
          return ListView(
            children: [
              SwitchListTile(
                title: const Text('All notifications'),
                subtitle: const Text('Turn all notifications on or off'),
                value: settings.enabled,
                activeColor: AppTheme.primaryColor,
                onChanged: (value) => _setEnabled(context, value),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Chat messages'),
                subtitle: const Text('Notify me about new messages'),
                value: settings.chatMessages,
                activeColor: AppTheme.primaryColor,
                onChanged:
                    settings.enabled ? (value) => _setChatMessages(context, value) : null,
              ),
              SwitchListTile(
                title: const Text('New matches'),
                subtitle: const Text('Notify me when I get a new match'),
                value: settings.matches,
                activeColor: AppTheme.primaryColor,
                onChanged:
                    settings.enabled ? (value) => _setMatches(context, value) : null,
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
        const SnackBar(content: Text('Could not update notification settings')),
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
        const SnackBar(content: Text('Could not update notification settings')),
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
        const SnackBar(content: Text('Could not update notification settings')),
      );
    }
  }
}
