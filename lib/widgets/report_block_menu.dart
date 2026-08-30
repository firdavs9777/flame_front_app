import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/providers/report_provider.dart';
import 'package:flame/services/report_service.dart';

/// Reporting and blocking, the two things a user needs when a conversation
/// goes wrong.
///
/// Everything here used to be hardcoded English in an app that ships 32
/// languages — the one flow where not understanding the buttons has real
/// consequences. It is now localised, and lives in functions rather than only
/// inside a menu widget so the chat header and a message long-press can open
/// the same sheets the profile screen does.

/// The localised label for a report reason. Lives here rather than on the enum
/// because the enum is a service-layer type with no BuildContext.
String reportReasonLabel(AppLocalizations l10n, ReportReason reason) {
  switch (reason) {
    case ReportReason.inappropriateContent:
      return l10n.safetyReasonInappropriate;
    case ReportReason.fakeProfile:
      return l10n.safetyReasonFakeProfile;
    case ReportReason.harassment:
      return l10n.safetyReasonHarassment;
    case ReportReason.spam:
      return l10n.safetyReasonSpam;
    case ReportReason.underage:
      return l10n.safetyReasonUnderage;
    case ReportReason.other:
      return l10n.safetyReasonOther;
  }
}

/// Asks for a reason and submits a report against [userId].
///
/// [messageId] reports one message rather than the person. Apple's UGC rules
/// expect the offending *content* to be reportable, not just its author, and a
/// moderator handling "harassment" can act far faster with the message in hand.
Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  String? messageId,
}) {
  final l10n = context.l10n;
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                messageId == null
                    ? l10n.safetyReportUserTitle
                    : l10n.safetyReportMessageTitle,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            for (final reason in ReportReason.values)
              ListTile(
                title: Text(reportReasonLabel(l10n, reason)),
                onTap: () => _submitReport(
                  context,
                  ref,
                  sheetContext,
                  userId: userId,
                  reason: reason,
                  messageId: messageId,
                ),
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
  BuildContext sheetContext, {
  required String userId,
  required ReportReason reason,
  String? messageId,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  Navigator.pop(sheetContext); // close the sheet while the context is alive
  final result = await ref.read(reportServiceProvider).reportUser(
        userId: userId,
        reason: reason,
        messageId: messageId,
      );
  messenger.showSnackBar(SnackBar(
    content: Text(
        result.success ? l10n.safetyReportSubmitted : l10n.safetyReportFailed),
  ));
}

/// Confirms, then blocks [userId]. Returns true if the block went through, so
/// the caller can leave a screen that is now about someone you cannot see.
Future<bool> confirmAndBlock(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String userName,
}) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.safetyBlockConfirmTitle(userName)),
      content: Text(l10n.safetyBlockConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.commonCancel),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.safetyBlock),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  final result = await ref.read(reportServiceProvider).blockUser(userId);
  messenger.showSnackBar(SnackBar(
    content: Text(result.success
        ? l10n.safetyBlocked(userName)
        : l10n.safetyBlockFailed),
  ));
  return result.success;
}

/// Overflow menu offering Report and Block for another user.
class ReportBlockMenu extends ConsumerWidget {
  final String userId;
  final String userName;

  const ReportBlockMenu({super.key, required this.userId, this.userName = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) async {
        if (value == 'report') {
          await showReportSheet(context, ref, userId: userId);
        } else if (value == 'block') {
          final blocked = await confirmAndBlock(context, ref,
              userId: userId, userName: userName);
          if (blocked && context.mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(value: 'report', child: Text(l10n.safetyReport)),
        PopupMenuItem<String>(value: 'block', child: Text(l10n.safetyBlock)),
      ],
    );
  }
}
