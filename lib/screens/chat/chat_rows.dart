import 'package:intl/intl.dart';

import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';

/// One entry in the rendered conversation: either a day separator or a message.
///
/// Separators are list items rather than decorations on a bubble, following
/// BananaTalk's `pages/chat/message/messages_list.dart`. That distinction
/// matters for grouping: a bubble cannot know a separator sits above it, so
/// "don't group across a day boundary" is only expressible once the separators
/// are in the list.
sealed class ChatRow {
  const ChatRow();
}

class DateSeparatorRow extends ChatRow {
  /// Midnight of the day being labelled.
  final DateTime day;
  const DateSeparatorRow(this.day);
}

class MessageRow extends ChatRow {
  final Message message;

  /// First of a run from one sender — carries the avatar.
  final bool isFirstInGroup;

  /// Last of a run — carries the timestamp and the delivery tick.
  final bool isLastInGroup;

  const MessageRow(
    this.message, {
    required this.isFirstInGroup,
    required this.isLastInGroup,
  });
}

/// How long a pause ends a group. Beyond this, two messages from one person are
/// two thoughts rather than one breath, and each deserves its own timestamp.
const Duration _groupGap = Duration(minutes: 5);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Whether [b] continues [a]'s group: same sender, close in time, same day.
bool _continues(Message a, Message b) {
  if (a.senderId != b.senderId) return false;
  if (!_sameDay(a.timestamp, b.timestamp)) return false;
  return b.timestamp.difference(a.timestamp).abs() <= _groupGap;
}

/// Turns messages, oldest first, into rows with day separators and grouping.
///
/// Pure, and deliberately so: every hard case here is a calendar case —
/// midnight, a day boundary landing inside a run — and none of them needs a
/// rendered widget to pin down.
///
/// Takes no clock. It used to accept a `now` it never read anywhere in its body:
/// the only clock-dependent decision is a separator's *label*, which
/// [chatDayLabel] makes at render time. Being a pure function of an immutable
/// list is what lets `MessageThreadState` memoize the result instead of
/// rebuilding every separator on every rebuild.
List<ChatRow> buildChatRows(List<Message> messages) {
  if (messages.isEmpty) return const [];

  final rows = <ChatRow>[];

  for (var i = 0; i < messages.length; i++) {
    final message = messages[i];
    final previous = i == 0 ? null : messages[i - 1];
    final next = i == messages.length - 1 ? null : messages[i + 1];

    if (previous == null || !_sameDay(previous.timestamp, message.timestamp)) {
      rows.add(DateSeparatorRow(DateTime(
        message.timestamp.year,
        message.timestamp.month,
        message.timestamp.day,
      )));
    }

    rows.add(MessageRow(
      message,
      isFirstInGroup: previous == null || !_continues(previous, message),
      isLastInGroup: next == null || !_continues(message, next),
    ));
  }

  return rows;
}

/// The label for a separator: today, yesterday, or a formatted date.
///
/// Compared by calendar day, not elapsed hours — at 00:30, something from 23:00
/// last night is "yesterday" even though barely ninety minutes have passed.
///
/// Called at render time rather than baked into the row, which is what lets a
/// session left open across midnight relabel itself.
///
/// [l10n] rather than hardcoded English: this shipped `Today` / `Yesterday` /
/// `Jan`…`Dec` in an app with thirteen locales and a working ARB pipeline. The
/// month name comes from [DateFormat] so it follows the active locale's own
/// conventions instead of a hand-written table.
String chatDayLabel(DateTime day, DateTime now, AppLocalizations l10n) {
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(day.year, day.month, day.day);
  final diff = today.difference(that).inDays;

  if (diff == 0) return l10n.chatDayToday;
  if (diff == 1) return l10n.chatDayYesterday;

  final locale = Intl.getCurrentLocale();
  return that.year == today.year
      ? DateFormat.MMMd(locale).format(that)
      : DateFormat.yMMMd(locale).format(that);
}
