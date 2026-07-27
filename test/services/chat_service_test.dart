import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/models/message.dart';
import 'package:flame/models/conversation.dart';

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

ApiClient _buildApiClient(_MockClient mock) {
  return ApiClient.testInstance(httpClient: mock);
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

  test('sendMessage posts text + reply_to and parses returned Message', () async {
    final messageJson = {
      'id': 'msg-1',
      'sender_id': 'user-1',
      'text': 'hello',
      'created_at': '2026-07-26T00:00:00Z',
    };
    final mock = _MockClient(http.Response(
      jsonEncode({'success': true, 'data': messageJson}),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = ChatService(apiClient: apiClient);

    final result = await service.sendMessage(
      'conv-1',
      'hello',
      replyToId: 'msg-0',
    );

    expect(result.success, true);
    expect(result.data!.id, 'msg-1');
    expect(result.data!.content, 'hello');

    final req = mock.calls.single as http.Request;
    expect(req.method, 'POST');
    expect(req.url.path.endsWith('/conversations/conv-1/messages'), true);
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['text'], 'hello');
    expect(body['reply_to'], 'msg-0');
    expect(body.containsKey('content'), false);
    expect(body.containsKey('type'), false);
    expect(body.containsKey('reply_to_id'), false);
  });

  test('sendMessage without replyToId omits reply_to', () async {
    final messageJson = {
      'id': 'msg-2',
      'sender_id': 'user-1',
      'text': 'hi',
      'created_at': '2026-07-26T00:00:00Z',
    };
    final mock = _MockClient(http.Response(
      jsonEncode({'success': true, 'data': messageJson}),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = ChatService(apiClient: apiClient);

    await service.sendMessage('conv-1', 'hi');

    final req = mock.calls.single as http.Request;
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['text'], 'hi');
    expect(body.containsKey('reply_to'), false);
  });

  test('getMessages uses offset query param and reads pagination.has_more', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'success': true,
        'data': {
          'messages': [
            {
              'id': 'msg-1',
              'sender_id': 'user-1',
              'text': 'hello',
              'created_at': '2026-07-26T00:00:00Z',
            }
          ],
          'pagination': {'has_more': true},
        },
      }),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = ChatService(apiClient: apiClient);

    final result = await service.getMessages('conv-1', offset: 50);

    expect(result.success, true);
    expect(result.data!.messages.length, 1);
    expect(result.data!.hasMore, true);

    final req = mock.calls.single as http.Request;
    expect(req.method, 'GET');
    expect(req.url.path.endsWith('/conversations/conv-1/messages'), true);
    expect(req.url.queryParameters['offset'], '50');
    expect(req.url.queryParameters.containsKey('before'), false);
  });

  test('getMessages defaults offset to 0', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'success': true,
        'data': {
          'messages': [],
          'pagination': {'has_more': false},
        },
      }),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = ChatService(apiClient: apiClient);

    await service.getMessages('conv-1');

    final req = mock.calls.single as http.Request;
    expect(req.url.queryParameters['offset'], '0');
  });

  test('markMessagesAsRead sends PUT with no body', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({'success': true, 'data': null}),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = ChatService(apiClient: apiClient);

    final result = await service.markMessagesAsRead('conv-1', ['msg-1', 'msg-2']);

    expect(result.success, true);

    final req = mock.calls.single as http.Request;
    expect(req.method, 'PUT');
    expect(req.url.path.endsWith('/conversations/conv-1/read'), true);
    expect(req.body.isEmpty, true);
  });

  test('addReaction posts to /messages/:id/reactions and returns Message', () async {
    final messageJson = {
      'id': 'msg-1',
      'sender_id': 'user-1',
      'text': 'hello',
      'created_at': '2026-07-26T00:00:00Z',
      'reactions': [
        {'emoji': 'heart', 'user_id': 'user-2'}
      ],
    };
    final mock = _MockClient(http.Response(
      jsonEncode({'success': true, 'data': messageJson}),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = ChatService(apiClient: apiClient);

    final result = await service.addReaction('conv-1', 'msg-1', 'love');

    expect(result.success, true);
    expect(result.data, isA<Message>());
    expect(result.data!.id, 'msg-1');

    final req = mock.calls.single as http.Request;
    expect(req.method, 'POST');
    expect(req.url.path.endsWith('/messages/msg-1/reactions'), true);
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['emoji'], 'love');
  });

  test('removeReaction deletes to /messages/:id/reactions and returns Message', () async {
    final messageJson = {
      'id': 'msg-1',
      'sender_id': 'user-1',
      'text': 'hello',
      'created_at': '2026-07-26T00:00:00Z',
    };
    final mock = _MockClient(http.Response(
      jsonEncode({'success': true, 'data': messageJson}),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = ChatService(apiClient: apiClient);

    final result = await service.removeReaction('conv-1', 'msg-1');

    expect(result.success, true);
    expect(result.data, isA<Message>());

    final req = mock.calls.single as http.Request;
    expect(req.method, 'DELETE');
    expect(req.url.path.endsWith('/messages/msg-1/reactions'), true);
  });

  test('editMessage PATCHes /messages/:id with {text} and parses Message', () async {
    final messageJson = {
      'id': 'msg-1',
      'sender_id': 'user-1',
      'text': 'edited hello',
      'is_edited': true,
      'edited_at': '2026-07-27T00:00:00Z',
      'created_at': '2026-07-26T00:00:00Z',
    };
    final mock = _MockClient(http.Response(
      jsonEncode({'success': true, 'data': messageJson}),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = ChatService(apiClient: apiClient);

    final result = await service.editMessage('msg-1', 'edited hello');

    expect(result.success, true);
    expect(result.data!.id, 'msg-1');
    expect(result.data!.content, 'edited hello');
    expect(result.data!.isEdited, true);

    final req = mock.calls.single as http.Request;
    expect(req.method, 'PATCH');
    expect(req.url.path.endsWith('/messages/msg-1'), true);
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body, {'text': 'edited hello'});
  });

  test('deleteMessage DELETEs /messages/:id with ?scope=me by default and parses Message', () async {
    final messageJson = {
      'id': 'msg-1',
      'sender_id': 'user-1',
      'text': 'hello',
      'is_deleted': true,
      'created_at': '2026-07-26T00:00:00Z',
    };
    final mock = _MockClient(http.Response(
      jsonEncode({'success': true, 'data': messageJson}),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = ChatService(apiClient: apiClient);

    final result = await service.deleteMessage('msg-1');

    expect(result.success, true);
    expect(result.data!.id, 'msg-1');
    expect(result.data!.isDeleted, true);

    final req = mock.calls.single as http.Request;
    expect(req.method, 'DELETE');
    expect(req.url.path.endsWith('/messages/msg-1'), true);
    expect(req.url.queryParameters['scope'], 'me');
  });

  test('deleteMessage passes scope=everyone through as a query param', () async {
    final messageJson = {
      'id': 'msg-1',
      'sender_id': 'user-1',
      'text': 'hello',
      'is_deleted': true,
      'created_at': '2026-07-26T00:00:00Z',
    };
    final mock = _MockClient(http.Response(
      jsonEncode({'success': true, 'data': messageJson}),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = ChatService(apiClient: apiClient);

    await service.deleteMessage('msg-1', scope: 'everyone');

    final req = mock.calls.single as http.Request;
    expect(req.url.queryParameters['scope'], 'everyone');
  });

  test('createConversation posts user_id and returns Conversation', () async {
    final conversationJson = {
      'id': 'conv-1',
      'other_user': {
        'id': 'user-2',
        'name': 'Alex',
      },
      'updated_at': '2026-07-26T00:00:00Z',
    };
    final mock = _MockClient(http.Response(
      jsonEncode({'success': true, 'data': conversationJson}),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = ChatService(apiClient: apiClient);

    final result = await service.createConversation('user-2');

    expect(result.success, true);
    expect(result.data, isA<Conversation>());
    expect(result.data!.id, 'conv-1');

    final req = mock.calls.single as http.Request;
    expect(req.method, 'POST');
    expect(req.url.path.endsWith('/conversations'), true);
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['user_id'], 'user-2');
  });
}
