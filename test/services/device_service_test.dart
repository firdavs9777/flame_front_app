import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flame/services/api_client.dart';
import 'package:flame/services/device_service.dart';

class _MockClient extends http.BaseClient {
  final List<http.BaseRequest> calls = [];
  final List<String> bodies = [];
  final http.Response queued;

  _MockClient(this.queued);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async {
    calls.add(req);
    if (req is http.Request) bodies.add(req.body);
    return http.StreamedResponse(
      Stream.value(utf8.encode(queued.body)),
      queued.statusCode,
      headers: queued.headers,
      request: req,
    );
  }
}

Future<ApiClient> _apiClient(_MockClient mock) async {
  final client = ApiClient.testInstance(httpClient: mock);
  await client.init();
  return client;
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

  test('registerToken POSTs camelCase keys to /notifications/register-token',
      () async {
    // The route validates with zod: `{ token, platform, deviceId }`. snake_case
    // here would be a 422, and the app would silently never receive a push.
    final mock = _MockClient(
      http.Response(jsonEncode({'success': true, 'data': {}}), 200),
    );
    final service = DeviceService(apiClient: await _apiClient(mock));

    final result = await service.registerToken(
      token: 'fcm-token-abc',
      platform: PushPlatform.android,
      deviceId: 'device-1',
    );

    expect(result.success, isTrue);
    expect(
      mock.calls.single.url.path,
      endsWith('/notifications/register-token'),
    );
    expect(mock.calls.single.method, 'POST');

    final body = jsonDecode(mock.bodies.single) as Map<String, dynamic>;
    expect(body, {
      'token': 'fcm-token-abc',
      'platform': 'android',
      'deviceId': 'device-1',
    });
  });

  test('platform is one of the two values the zod enum accepts', () {
    expect(PushPlatform.android, 'android');
    expect(PushPlatform.ios, 'ios');
  });

  test('removeToken DELETEs the device id in the path', () async {
    final mock = _MockClient(
      http.Response(jsonEncode({'success': true, 'data': {}}), 200),
    );
    final service = DeviceService(apiClient: await _apiClient(mock));

    final result = await service.removeToken('device-1');

    expect(result.success, isTrue);
    expect(mock.calls.single.method, 'DELETE');
    expect(
      mock.calls.single.url.path,
      endsWith('/notifications/remove-token/device-1'),
    );
  });

  test('a rejected registration reports failure instead of throwing', () async {
    final mock = _MockClient(
      http.Response(
        jsonEncode({'success': false, 'error': 'validation failed'}),
        422,
      ),
    );
    final service = DeviceService(apiClient: await _apiClient(mock));

    final result = await service.registerToken(
      token: 't',
      platform: PushPlatform.android,
      deviceId: 'd',
    );

    expect(result.success, isFalse);
    expect(result.error, isNotNull);
  });
}
