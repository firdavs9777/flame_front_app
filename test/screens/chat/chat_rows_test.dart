import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/chat/chat_rows.dart';

Message _msg(String id, String senderId, DateTime at) => Message.fromJson({
  'id': id,
  'sender_id': senderId,
  'text': 'hi',
  'type': 'text',
  'created_at': at.toIso8601String(),
});

// A month-long conversation used to render as one undifferentiated wall: a flat
// ListView over messages, no day boundaries, and a fresh avatar and timestamp on
// every message even in a run of five from the same person.
//
// Building rows is a pure transform, which matters because every hard case here
// is a calendar case — midnight, a day boundary inside a run, "Today" versus a
// date — and none of it needs a widget to test.
void main() {
  final day1 = DateTime(2026, 8, 15, 10, 0);
  final day2 = DateTime(2026, 8, 16, 10, 0);

  group('date separators', () {
    test('an empty conversation has no rows', () {
      expect(buildChatRows(const [], now: day2), isEmpty);
    });

    test('one message gets one separator above it', () {
      final rows = buildChatRows([_msg('m1', 'a', day1)], now: day2);

      expect(rows.length, 2);
      expect(rows.first, isA<DateSeparatorRow>());
      expect(rows.last, isA<MessageRow>());
    });

    test('messages on the same day share one separator', () {
      final rows = buildChatRows([
        _msg('m1', 'a', day1),
        _msg('m2', 'a', day1.add(const Duration(hours: 3))),
      ], now: day2);

      expect(rows.whereType<DateSeparatorRow>().length, 1);
      expect(rows.whereType<MessageRow>().length, 2);
    });

    test('a new day gets its own separator', () {
      final rows = buildChatRows([
        _msg('m1', 'a', day1),
        _msg('m2', 'a', day2),
      ], now: day2);

      expect(rows.whereType<DateSeparatorRow>().length, 2);
    });

    test('messages minutes apart across midnight are two days, not one', () {
      final rows = buildChatRows([
        _msg('m1', 'a', DateTime(2026, 8, 15, 23, 58)),
        _msg('m2', 'a', DateTime(2026, 8, 16, 0, 2)),
      ], now: day2);

      expect(rows.whereType<DateSeparatorRow>().length, 2,
          reason: 'four minutes apart, but a different calendar day');
    });
  });

  group('separator labels', () {
    test('today and yesterday are named, not dated', () {
      final now = DateTime(2026, 8, 16, 15, 0);

      expect(chatDayLabel(DateTime(2026, 8, 16, 9, 0), now), 'Today');
      expect(chatDayLabel(DateTime(2026, 8, 15, 9, 0), now), 'Yesterday');
    });

    test('anything older gets a date', () {
      final now = DateTime(2026, 8, 16, 15, 0);
      final label = chatDayLabel(DateTime(2026, 8, 10, 9, 0), now);

      expect(label, isNot('Today'));
      expect(label, isNot('Yesterday'));
      expect(label, contains('10'));
    });

    test('"today" is a calendar day, not 24 hours', () {
      // 00:30 today is "Today" even though it is more than 24 hours after
      // 23:00 two days ago.
      final now = DateTime(2026, 8, 16, 0, 30);
      expect(chatDayLabel(DateTime(2026, 8, 16, 0, 5), now), 'Today');
      expect(chatDayLabel(DateTime(2026, 8, 15, 23, 0), now), 'Yesterday');
    });
  });

  group('grouping', () {
    test('a lone message is both first and last in its group', () {
      final rows = buildChatRows([_msg('m1', 'a', day1)], now: day2);
      final row = rows.whereType<MessageRow>().single;

      expect(row.isFirstInGroup, isTrue);
      expect(row.isLastInGroup, isTrue);
    });

    test('a run from one sender is grouped', () {
      final rows = buildChatRows([
        _msg('m1', 'a', day1),
        _msg('m2', 'a', day1.add(const Duration(minutes: 1))),
        _msg('m3', 'a', day1.add(const Duration(minutes: 2))),
      ], now: day2);
      final msgs = rows.whereType<MessageRow>().toList();

      expect(msgs[0].isFirstInGroup, isTrue);
      expect(msgs[0].isLastInGroup, isFalse);
      expect(msgs[1].isFirstInGroup, isFalse);
      expect(msgs[1].isLastInGroup, isFalse);
      expect(msgs[2].isFirstInGroup, isFalse);
      expect(msgs[2].isLastInGroup, isTrue,
          reason: 'only the last of a run carries the timestamp');
    });

    test('a different sender starts a new group', () {
      final rows = buildChatRows([
        _msg('m1', 'a', day1),
        _msg('m2', 'b', day1.add(const Duration(minutes: 1))),
      ], now: day2);
      final msgs = rows.whereType<MessageRow>().toList();

      expect(msgs[0].isLastInGroup, isTrue);
      expect(msgs[1].isFirstInGroup, isTrue);
    });

    test('a long gap breaks a group even from the same sender', () {
      final rows = buildChatRows([
        _msg('m1', 'a', day1),
        _msg('m2', 'a', day1.add(const Duration(hours: 2))),
      ], now: day2);
      final msgs = rows.whereType<MessageRow>().toList();

      expect(msgs[0].isLastInGroup, isTrue,
          reason: 'two hours later is a new thought, not the same breath');
      expect(msgs[1].isFirstInGroup, isTrue);
    });

    test('a day boundary breaks a group even within the gap window', () {
      final rows = buildChatRows([
        _msg('m1', 'a', DateTime(2026, 8, 15, 23, 58)),
        _msg('m2', 'a', DateTime(2026, 8, 16, 0, 2)),
      ], now: day2);
      final msgs = rows.whereType<MessageRow>().toList();

      // Four minutes apart and the same sender, but a separator sits between
      // them — grouping across it would render an orphaned bubble under a date.
      expect(msgs[0].isLastInGroup, isTrue);
      expect(msgs[1].isFirstInGroup, isTrue);
    });
  });
}
