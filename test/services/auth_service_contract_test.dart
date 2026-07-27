import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/auth_service.dart';

class _MockClient extends http.BaseClient {
  final List<http.BaseRequest> calls = [];
  final http.Response queued;
  _MockClient(this.queued);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async {
    calls.add(req);
    // Buffer the request body so tests can assert on it after the call.
    if (req is http.Request) {
      // ignore: unnecessary_statements
      req.body;
    }
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
    SharedPreferences.setMockInitialValues({});
  });

  test('register sends camelCase lookingFor (not looking_for) plus coords + photos',
      () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'success': true,
        'data': {
          'user': {'id': 'u1', 'name': 'Ada'},
          'tokens': {'accessToken': 'AT', 'refreshToken': 'RT'},
        },
      }),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = AuthService(apiClient: apiClient);

    final result = await service.register(
      email: 'ada@example.com',
      password: 'Password1',
      name: 'Ada',
      age: 30,
      gender: Gender.female,
      lookingFor: Gender.male,
      bio: 'hi',
      interests: const ['Music'],
      photos: const ['https://cdn/1.jpg', 'https://cdn/2.jpg'],
      latitude: 37.42,
      longitude: -122.08,
    );

    expect(result.success, true);

    final req = mock.calls.single as http.Request;
    expect(req.method, 'POST');
    expect(req.url.path.endsWith('/auth/register'), true);

    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body.containsKey('lookingFor'), true);
    expect(body.containsKey('looking_for'), false);
    expect(body['lookingFor'], 'male');
    expect(body['latitude'], 37.42);
    expect(body['longitude'], -122.08);
    expect(body['photos'], ['https://cdn/1.jpg', 'https://cdn/2.jpg']);
  });

  test('googleSignIn reads camelCase tokens and saves them', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'success': true,
        'data': {
          'user': {'id': 'u2', 'name': 'Grace'},
          'tokens': {'accessToken': 'AT_camel', 'refreshToken': 'RT_camel'},
        },
      }),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = AuthService(apiClient: apiClient);

    final result = await service.googleSignIn(idToken: 'google-id-token');

    expect(result.success, true);
    expect(result.user, isNotNull);
    // Camel-first token read persisted the token.
    expect(apiClient.accessToken, 'AT_camel');

    final req = mock.calls.single as http.Request;
    expect(req.url.path.endsWith('/auth/google'), true);
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['id_token'], 'google-id-token');
  });

  test('facebookSignIn also accepts snake_case tokens (dual-casing)', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'success': true,
        'data': {
          'user': {'id': 'u3', 'name': 'Alan'},
          'tokens': {'access_token': 'AT_snake', 'refresh_token': 'RT_snake'},
        },
      }),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = AuthService(apiClient: apiClient);

    final result = await service.facebookSignIn(accessToken: 'fb-access-token');

    expect(result.success, true);
    expect(apiClient.accessToken, 'AT_snake');
  });
}
