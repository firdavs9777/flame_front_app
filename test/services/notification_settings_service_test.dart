import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/notification_settings_service.dart';

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

  test('getSettings GETs /notifications/settings and parses snake_case response',
      () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'success': true,
        'data': {
          'enabled': true,
          'chat_messages': false,
          'matches': true,
        },
      }),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = NotificationSettingsService(apiClient: apiClient);

    final result = await service.getSettings();

    expect(result.success, true);
    expect(result.data!.enabled, true);
    expect(result.data!.chatMessages, false);
    expect(result.data!.matches, true);

    final req = mock.calls.single as http.Request;
    expect(req.method, 'GET');
    expect(req.url.path.endsWith('/notifications/settings'), true);
  });

  test('getSettings surfaces failure from the API', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'error': {'message': 'nope'},
      }),
      500,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = NotificationSettingsService(apiClient: apiClient);

    final result = await service.getSettings();

    expect(result.success, false);
    expect(result.data, isNull);
  });

  test('updateSettings PUTs only the provided field as camelCase and parses response',
      () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'success': true,
        'data': {
          'enabled': true,
          'chat_messages': false,
          'matches': true,
        },
      }),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = NotificationSettingsService(apiClient: apiClient);

    final result = await service.updateSettings(chatMessages: false);

    expect(result.success, true);
    expect(result.data!.chatMessages, false);

    final req = mock.calls.single as http.Request;
    expect(req.method, 'PUT');
    expect(req.url.path.endsWith('/notifications/settings'), true);
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body, {'chatMessages': false});
  });

  test('updateSettings sends multiple provided fields, omitting unset ones',
      () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'success': true,
        'data': {
          'enabled': false,
          'chat_messages': false,
          'matches': false,
        },
      }),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = NotificationSettingsService(apiClient: apiClient);

    await service.updateSettings(enabled: false, matches: false);

    final req = mock.calls.single as http.Request;
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body, {'enabled': false, 'matches': false});
    expect(body.containsKey('chatMessages'), false);
  });

  test('updateSettings surfaces failure from the API', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'error': {'message': 'nope'},
      }),
      400,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = NotificationSettingsService(apiClient: apiClient);

    final result = await service.updateSettings(enabled: false);

    expect(result.success, false);
    expect(result.data, isNull);
  });
}
