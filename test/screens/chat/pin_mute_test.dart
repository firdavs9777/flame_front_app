import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flame/models/models.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/chat_service.dart';

class _MockClient extends http.BaseClient {
  final List<http.BaseRequest> calls = [];
  final http.Response queued;
  _MockClient(this.queued);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async {
    calls.add(req);
    return http.StreamedResponse(
      Stream.value(utf8.encode(queued.body)),
      queued.statusCode,
      headers: queued.headers,
      request: req,
    );
  }
}

Future<ChatService> _service(_MockClient mock) async {
  final apiClient = ApiClient.testInstance(httpClient: mock);
  await apiClient.init();
  return ChatService(apiClient: apiClient);
}

// Pin and mute have had working backends and app service calls for a while with
// no UI. Part of the reason was that the app could not read the state: nothing
// in the conversation payload said whether it was muted, and pins came back
// only from the mutators. The backend now supplies both; this covers the app
// half.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'access_token': 'token',
      'refresh_token': 'refresh',
    });
  });

  group('Conversation.isMuted', () {
    Conversation parse(Map<String, dynamic> extra) => Conversation.fromJson({
      'id': 'c1',
      'other_user': {'id': 'u1', 'name': 'Ada'},
      'unread_count': 0,
      'last_message_at': '2026-08-17T00:00:00.000Z',
      ...extra,
    });

    test('reads is_muted', () {
      expect(parse({'is_muted': true}).isMuted, isTrue);
      expect(parse({'is_muted': false}).isMuted, isFalse);
    });

    test('defaults to false when the field is absent', () {
      // An older backend does not send it, and a conversation that silently
      // reads as muted would hide notifications with no way to see why.
      expect(parse({}).isMuted, isFalse);
    });

    test('copyWith carries it', () {
      final muted = parse({'is_muted': true});
      expect(muted.copyWith(unreadCount: 3).isMuted, isTrue);
    });
  });

  group('getPinnedMessages', () {
    test('GETs the pins path and parses them', () async {
      final mock = _MockClient(http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'pinned_messages': [
              {
                'message_id': 'm1',
                'content': 'meet at seven',
                'pinned_by': 'u1',
                'pinned_at': '2026-08-17T00:00:00.000Z',
              },
            ],
          },
        }),
        200,
      ));
      final service = await _service(mock);

      final result = await service.getPinnedMessages('c1');

      expect(result.success, true);
      expect(result.data!.single.messageId, 'm1');
      expect(result.data!.single.content, 'meet at seven',
          reason: 'a bar showing an id instead of the message is not a bar');

      final req = mock.calls.single;
      expect(req.method, 'GET');
      expect(req.url.path.endsWith('/conversations/c1/pins'), true);
    });

    test('an empty list is success, not failure', () async {
      final mock = _MockClient(http.Response(
        jsonEncode({'success': true, 'data': {'pinned_messages': []}}),
        200,
      ));
      final service = await _service(mock);

      final result = await service.getPinnedMessages('c1');

      expect(result.success, true);
      expect(result.data, isEmpty);
    });

    test('a missing key yields an empty list rather than throwing', () async {
      final mock = _MockClient(http.Response(
        jsonEncode({'success': true, 'data': {}}),
        200,
      ));
      final service = await _service(mock);

      final result = await service.getPinnedMessages('c1');

      expect(result.success, true);
      expect(result.data, isEmpty);
    });
  });
}
