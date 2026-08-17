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
/// midnight, a day boundary landing inside a run, "Today" versus a date — and
/// none of them needs a rendered widget to pin down.
///
/// [now] is injected rather than read from the clock so the label tests are not
/// hostage to the day they run on.
List<ChatRow> buildChatRows(List<Message> messages, {required DateTime now}) {
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

/// The label for a separator: `Today`, `Yesterday`, or a date.
///
/// Compared by calendar day, not elapsed hours — at 00:30, something from 23:00
/// last night is "Yesterday" even though barely ninety minutes have passed.
String chatDayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(day.year, day.month, day.day);
  final diff = today.difference(that).inDays;

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final label = '${months[that.month - 1]} ${that.day}';
  return that.year == today.year ? label : '$label, ${that.year}';
}
