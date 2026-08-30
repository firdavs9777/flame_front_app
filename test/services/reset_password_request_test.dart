import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/auth_service.dart';

// resetPassword was deleted in the auth-surface cleanup because nothing on the
// server answered it. Both routes exist now, so the client needs it back — and
// needs to send exactly what the server validates: a six digit `code` beside
// the email, not the `token` the old link-based shape assumed.

class _MockClient extends http.BaseClient {
  final List<http.Request> calls = [];
  final http.Response queued;
  _MockClient(this.queued);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async {
    if (req is http.Request) calls.add(req);
    return http.StreamedResponse(
      Stream.value(utf8.encode(queued.body)),
      queued.statusCode,
      headers: queued.headers,
      request: req,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('resetPassword posts email, code and the new password', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({'success': true, 'message': 'Password updated.'}),
      200,
      headers: {'content-type': 'application/json'},
    ));
    final service = AuthService(apiClient: ApiClient.testInstance(httpClient: mock));

    final result = await service.resetPassword(
      email: 'me@x.com',
      code: '483916',
      password: 'brand-new-password',
    );

    expect(result.success, isTrue);
    final req = mock.calls.single;
    expect(req.url.path, endsWith('/auth/reset-password'));
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['email'], 'me@x.com');
    expect(body['code'], '483916');
    expect(body['password'], 'brand-new-password');
    expect(body.containsKey('token'), isFalse,
        reason: 'the server validates a code, and rejects unknown keys');
  });

  test('surfaces the server error on a bad code', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'success': false,
        'error': {'code': 'VALIDATION', 'message': 'Invalid or expired reset code'},
      }),
      422,
      headers: {'content-type': 'application/json'},
    ));
    final service = AuthService(apiClient: ApiClient.testInstance(httpClient: mock));

    final result = await service.resetPassword(
      email: 'me@x.com', code: '000000', password: 'brand-new-password');

    expect(result.success, isFalse);
    expect(result.error, isNotNull);
  });
}
