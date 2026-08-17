import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'access_token': 'token',
      'refresh_token': 'refresh',
    });
  });

  group('archive', () {
    test('archiveConversation POSTs to the archive path', () async {
      final mock = _MockClient(http.Response(
        jsonEncode({'success': true, 'data': {'archived': true}}),
        200,
      ));
      final service = await _service(mock);

      final result = await service.archiveConversation('conv-1');

      expect(result.success, true);
      final req = mock.calls.single;
      expect(req.method, 'POST');
      expect(req.url.path.endsWith('/conversations/conv-1/archive'), true);
    });

    test('unarchiveConversation issues a DELETE, not a POST with a flag', () async {
      final mock = _MockClient(http.Response(
        jsonEncode({'success': true, 'data': {'archived': false}}),
        200,
      ));
      final service = await _service(mock);

      final result = await service.unarchiveConversation('conv-1');

      expect(result.success, true);
      final req = mock.calls.single;
      // The mute pair shipped with exactly this mistake: the app POSTed
      // {duration_hours: 0} to /mute as its "unmute", which silenced the
      // conversation permanently and reported success.
      expect(req.method, 'DELETE');
      expect(req.url.path.endsWith('/conversations/conv-1/archive'), true);
    });

    test('a failure surfaces the server message', () async {
      final mock = _MockClient(http.Response(
        jsonEncode({
          'success': false,
          'error': {'code': 'FORBIDDEN', 'message': 'not your conversation'},
        }),
        403,
      ));
      final service = await _service(mock);

      final result = await service.archiveConversation('conv-1');

      expect(result.success, false);
      expect(result.error, contains('not your conversation'));
    });

    test('getConversations asks for the archived side when told to', () async {
      final mock = _MockClient(http.Response(
        jsonEncode({
          'success': true,
          'data': {'conversations': [], 'pagination': {'total': 0}},
        }),
        200,
      ));
      final service = await _service(mock);

      await service.getConversations(archived: true);

      expect(mock.calls.single.url.queryParameters['archived'], 'true');
    });

    test('getConversations defaults to the un-archived side', () async {
      final mock = _MockClient(http.Response(
        jsonEncode({
          'success': true,
          'data': {'conversations': [], 'pagination': {'total': 0}},
        }),
        200,
      ));
      final service = await _service(mock);

      await service.getConversations();

      expect(mock.calls.single.url.queryParameters['archived'], 'false');
    });
  });

  group('search', () {
    test('passes the query through queryParams, not the path', () async {
      final mock = _MockClient(http.Response(
        jsonEncode({'success': true, 'data': {'messages': [], 'total': 0}}),
        200,
      ));
      final service = await _service(mock);

      await service.searchMessages(query: 'sushi & rice', limit: 5, offset: 10);

      final req = mock.calls.single;
      expect(req.method, 'GET');
      expect(req.url.path.endsWith('/messages/search'), true);
      // Concatenating into the path would double-encode the ampersand and
      // truncate the query at it.
      expect(req.url.queryParameters['q'], 'sushi & rice');
      expect(req.url.queryParameters['limit'], '5');
      expect(req.url.queryParameters['offset'], '10');
    });

    test('parses the returned messages', () async {
      final mock = _MockClient(http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'messages': [
              {
                'id': 'm1',
                'sender_id': 'u1',
                'text': 'shall we get sushi',
                'created_at': '2026-08-17T00:00:00Z',
                'conversation_id': 'c1',
              },
            ],
            'total': 1,
          },
        }),
        200,
      ));
      final service = await _service(mock);

      final result = await service.searchMessages(query: 'sushi');

      expect(result.success, true);
      expect(result.data!.single.id, 'm1');
      expect(result.data!.single.content, 'shall we get sushi');
    });

    test('a response with no messages key yields an empty list, not a throw', () async {
      final mock = _MockClient(http.Response(
        jsonEncode({'success': true, 'data': {'total': 0}}),
        200,
      ));
      final service = await _service(mock);

      final result = await service.searchMessages(query: 'sushi');

      expect(result.success, true);
      expect(result.data, isEmpty);
    });

    test('a rate limit is reported as a failure the UI can localise', () async {
      final mock = _MockClient(http.Response(
        jsonEncode({
          'success': false,
          'error': {'code': 'RATE_LIMITED', 'message': 'Too many searches.'},
        }),
        429,
      ));
      final service = await _service(mock);

      final result = await service.searchMessages(query: 'sushi');

      expect(result.success, false);
      // ApiClient deliberately normalises 429 to its own code rather than
      // passing the server's English through — the UI localises it via
      // translateApiError(). Asserting the server's wording here would pin
      // behaviour the app does not actually have.
      expect(result.error, 'Rate limited');
    });

    test('a non-rate-limit failure surfaces the server message', () async {
      final mock = _MockClient(http.Response(
        jsonEncode({
          'success': false,
          'error': {'code': 'VALIDATION', 'message': 'q is required'},
        }),
        422,
      ));
      final service = await _service(mock);

      final result = await service.searchMessages(query: 'sushi');

      expect(result.success, false);
      expect(result.error, contains('q is required'));
    });
  });
}
