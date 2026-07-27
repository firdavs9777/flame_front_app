import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/message.dart';

Map<String, dynamic> _backendMsg({dynamic replyTo}) => {
      'id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 'u1',
      'receiver_id': 'u2',
      'text': 'hello there',
      'message_type': 'text',
      'reactions': [
        {'user_id': 'u2', 'emoji': '❤️'}
      ],
      'reply_to': replyTo,
      'read': true,
      'read_at': '2026-07-20T10:00:00.000Z',
      'created_at': '2026-07-20T09:59:00.000Z',
    };

void main() {
  test('parses backend snake_case message fields', () {
    final m = Message.fromJson(_backendMsg());
    expect(m.id, 'm1');
    expect(m.senderId, 'u1');
    expect(m.content, 'hello there'); // from `text`
    expect(m.type, MessageType.text); // from `message_type`
    expect(m.status, MessageStatus.read); // derived from `read: true`
    expect(m.timestamp.year, 2026); // from `created_at`
    expect(m.reactions.length, 1);
    expect(m.reactions.first.emoji, '❤️');
  });

  test('reply_to as a scalar id does not throw and is captured', () {
    final m = Message.fromJson(_backendMsg(replyTo: 'm0'));
    expect(m.replyTo, isNotNull);
    // The referenced id is retained on the messageId field.
    expect(m.replyTo!.messageId, 'm0');
  });

  test('null reply_to is fine', () {
    final m = Message.fromJson(_backendMsg(replyTo: null));
    expect(m.replyTo, isNull);
  });

  test('unread message derives a non-read status', () {
    final j = _backendMsg()..['read'] = false;
    final m = Message.fromJson(j);
    expect(m.status == MessageStatus.read, isFalse);
  });

  test('parses is_edited and edited_at from an edited message', () {
    final j = _backendMsg()
      ..['is_edited'] = true
      ..['edited_at'] = '2026-07-27T08:00:00.000Z';
    final m = Message.fromJson(j);
    expect(m.isEdited, true);
    expect(m.editedAt, isNotNull);
    expect(m.editedAt!.year, 2026);
    expect(m.editedAt!.month, 7);
    expect(m.editedAt!.day, 27);
  });

  test('is_edited defaults to false and edited_at to null when absent', () {
    final m = Message.fromJson(_backendMsg());
    expect(m.isEdited, false);
    expect(m.editedAt, isNull);
  });

  test('parses is_deleted from a tombstoned message', () {
    final j = _backendMsg()..['is_deleted'] = true;
    final m = Message.fromJson(j);
    expect(m.isDeleted, true);
  });

  test('is_deleted defaults to false when absent', () {
    final m = Message.fromJson(_backendMsg());
    expect(m.isDeleted, false);
  });
}
