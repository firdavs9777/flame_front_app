import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/services/report_service.dart';
import 'package:flame/providers/report_provider.dart';

/// Overflow menu offering Report (with a reason) and Block for another user.
/// Reachable wherever a user's profile is shown.
class ReportBlockMenu extends ConsumerWidget {
  final String userId;
  final String userName;

  const ReportBlockMenu({super.key, required this.userId, this.userName = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'report') {
          _showReportSheet(context, ref);
        } else if (value == 'block') {
          _confirmBlock(context, ref);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem<String>(value: 'report', child: Text('Report')),
        PopupMenuItem<String>(value: 'block', child: Text('Block')),
      ],
    );
  }

  void _showReportSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Report this user',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              for (final reason in ReportReason.values)
                ListTile(
                  title: Text(reason.displayName),
                  onTap: () => _submitReport(context, ref, sheetContext, reason),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitReport(
    BuildContext context,
    WidgetRef ref,
    BuildContext sheetContext,
    ReportReason reason,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(sheetContext); // close the sheet (sync, pre-await)
    final result =
        await ref.read(reportServiceProvider).reportUser(userId: userId, reason: reason);
    messenger.showSnackBar(SnackBar(
      content: Text(result.success
          ? 'Report submitted. Thank you.'
          : 'Could not submit report'),
    ));
  }

  Future<void> _confirmBlock(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block ${userName.isEmpty ? 'this user' : userName}?'),
        content: const Text("You won't see each other anymore."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await ref.read(reportServiceProvider).blockUser(userId);
    messenger.showSnackBar(SnackBar(
      content: Text(result.success ? 'User blocked' : 'Could not block user'),
    ));
    if (result.success && navigator.canPop()) {
      navigator.pop();
    }
  }
}
