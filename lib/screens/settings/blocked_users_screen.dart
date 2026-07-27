import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/providers/blocked_users_provider.dart';
import 'package:flame/services/report_service.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/kit/kit.dart';
import 'package:intl/intl.dart';

class BlockedUsersScreen extends ConsumerStatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        ref.read(blockedUsersProvider.notifier).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(blockedUsersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked Users')),
      body: state.when(
        loading: () => const Center(child: AppLoading()),
        error: (error, stack) => AppErrorState(
          title: 'Could not load blocked users',
          message: '$error',
          onRetry: () => ref.read(blockedUsersProvider.notifier).load(),
        ),
        data: (blocked) {
          if (blocked.isEmpty) {
            return const AppEmptyState(
              icon: Icons.block,
              title: "You haven't blocked anyone yet.",
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(blockedUsersProvider.notifier).refresh(),
            child: ListView.separated(
              itemCount: blocked.length,
              separatorBuilder: (_, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final user = blocked[index];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(user.name),
                  subtitle: Text('Blocked ${_formatDate(user.blockedAt)}'),
                  trailing: TextButton(
                    onPressed: () => _confirmUnblock(context, user),
                    child: const Text('Unblock'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) => DateFormat.yMMMd().format(date);

  Future<void> _confirmUnblock(BuildContext context, BlockedUser user) async {
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unblock user?'),
        content: Text('${user.name} will be able to see your profile and match with you again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Unblock',
              style: TextStyle(color: AppTheme.primaryColor),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    final ok = await ref.read(blockedUsersProvider.notifier).unblock(user.id);
    if (!context.mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok ? '${user.name} has been unblocked' : 'Could not unblock ${user.name}',
        ),
      ),
    );
  }
}
