import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';

Map<String, dynamic> _msg(String id, String text) => {
      'id': id,
      'sender_id': 'u2',
      'text': text,
      'created_at': '2026-08-18T10:00:00.000Z',
    };

Map<String, dynamic> _base(Map<String, dynamic> extra) => {
      'id': 'c1',
      'other_user': {'id': 'u2', 'name': 'B', 'photos': []},
      'updated_at': '2026-08-18T10:00:00.000Z',
      ...extra,
    };

void main() {
  group('Conversation.lastMessage', () {
    test('reads last_message from the list payload', () {
      final c = Conversation.fromJson(_base({'last_message': _msg('m5', 'newest')}));

      expect(c.lastMessage?.id, 'm5');
      expect(c.lastMessagePreview, 'newest');
    });

    test('falls back to the legacy messages array, newest last', () {
      final c = Conversation.fromJson(
          _base({'messages': [_msg('m4', 'older'), _msg('m5', 'newest')]}));

      expect(c.lastMessage?.id, 'm5',
          reason: 'preserves the ordering the old messages.last getter assumed');
    });

    test('last_message wins over the legacy array', () {
      final c = Conversation.fromJson(_base({
        'messages': [_msg('m4', 'older')],
        'last_message': _msg('m5', 'newest'),
      }));

      expect(c.lastMessage?.id, 'm5');
    });

    test('no message at all yields the say-hello preview', () {
      final c = Conversation.fromJson(_base({}));

      expect(c.lastMessage, isNull);
      expect(c.lastMessagePreview, 'Say hello!');
    });

    test('an empty legacy array is not a message', () {
      final c = Conversation.fromJson(_base({'messages': <dynamic>[]}));

      expect(c.lastMessage, isNull);
    });

    test('preview truncates at 40 characters', () {
      final c = Conversation.fromJson(
          _base({'last_message': _msg('m1', 'x' * 45)}));

      expect(c.lastMessagePreview, '${'x' * 40}...');
    });

    test('an image preview names the kind rather than showing empty text', () {
      final c = Conversation.fromJson(_base({
        'last_message': {..._msg('m1', ''), 'message_type': 'image'},
      }));

      expect(c.lastMessagePreview, '📷 Photo');
    });

    test('copyWith replaces lastMessage and keeps the rest', () {
      final c = Conversation.fromJson(_base({'last_message': _msg('m1', 'first')}));

      final next = c.copyWith(lastMessage: Message.fromJson(_msg('m2', 'second')));

      expect(next.lastMessage?.id, 'm2');
      expect(next.id, 'c1');
      expect(next.otherUser.id, 'u2');
    });

    test('toJson round-trips lastMessage', () {
      final c = Conversation.fromJson(_base({'last_message': _msg('m1', 'hi')}));

      final again = Conversation.fromJson(c.toJson());

      expect(again.lastMessage?.id, 'm1');
      expect(again.lastMessagePreview, 'hi');
    });

    test('unread and mute survive the round trip', () {
      final c = Conversation.fromJson(
          _base({'unread_count': 4, 'is_muted': true}));

      final again = Conversation.fromJson(c.toJson());

      expect(again.unreadCount, 4);
      expect(again.hasUnread, isTrue);
      expect(again.isMuted, isTrue);
    });
  });
}
