import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flame/services/api_client.dart';

class _FakeClient extends http.BaseClient {
  final List<http.BaseRequest> calls = [];
  final List<http.Response> queue;
  _FakeClient(this.queue);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async {
    calls.add(req);
    final resp = queue.removeAt(0);
    return http.StreamedResponse(
      Stream.value(utf8.encode(resp.body)),
      resp.statusCode,
      headers: resp.headers,
      request: req,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'access_token': 'old',
      'refresh_token': 'r',
    });
  });

  test('401 triggers refresh once for concurrent calls', () async {
    final fake = _FakeClient([
      http.Response('{}', 401),
      http.Response('{}', 401),
      http.Response('{"access_token":"new","refresh_token":"r"}', 200),
      http.Response('{"ok":true}', 200),
      http.Response('{"ok":true}', 200),
    ]);
    final client = ApiClient.testInstance(httpClient: fake);
    await client.init();
    final f1 = client.get('/x');
    final f2 = client.get('/y');
    final r1 = await f1;
    final r2 = await f2;
    expect(r1, isNotNull);
    expect(r2, isNotNull);
    final refreshCalls =
        fake.calls.where((c) => c.url.path.endsWith('/auth/refresh')).length;
    expect(refreshCalls, 1);
  });

  // The socket captures its auth token once, at construction, and socket.io
  // replays that same string on every automatic reconnect — so after a refresh
  // it is holding one the server will reject forever. A refresh updates
  // _accessToken here and never touches authProvider, which was the only thing
  // re-driving the connection, so nothing else can notice. This hook is what
  // MainShell listens to.
  test('a successful refresh notifies onTokenRefreshed with the new token',
      () async {
    final fake = _FakeClient([
      http.Response('{}', 401),
      http.Response('{"access_token":"fresh","refresh_token":"r2"}', 200),
      http.Response('{"ok":true}', 200),
    ]);
    final client = ApiClient.testInstance(httpClient: fake);
    await client.init();

    final seen = <String>[];
    client.onTokenRefreshed = seen.add;

    await client.get('/x');

    expect(seen, ['fresh'],
        reason: 'the realtime socket has no other way to learn its token died');
    expect(client.accessToken, 'fresh',
        reason: 'the hook must fire after the new token is stored, so a '
            'listener reading it back sees the same value');
  });

  test('a failed refresh does not notify onTokenRefreshed', () async {
    final fake = _FakeClient([
      http.Response('{}', 401),
      http.Response('{"error":"nope"}', 401),
    ]);
    final client = ApiClient.testInstance(httpClient: fake);
    await client.init();

    var called = false;
    client.onTokenRefreshed = (_) => called = true;

    await client.get('/x');

    expect(called, isFalse);
  });

  // The bug this file missed for as long as it existed: the fake above answers
  // in snake_case, which is what _doRefresh expected — not what the backend
  // sends. Every real refresh failed, and the app reads a failed refresh as
  // auth-lost, so the user landed on the welcome screen once the 15-minute
  // access token expired.
  test('refresh survives the camelCase response the backend actually sends', () async {
    final fake = _FakeClient([
      http.Response('{}', 401),
      // The real shape: { success: true, data: { accessToken, refreshToken } }.
      http.Response(
        jsonEncode({
          'success': true,
          'data': {'accessToken': 'new', 'refreshToken': 'r2'},
        }),
        200,
      ),
      http.Response('{"ok":true}', 200),
    ]);
    final client = ApiClient.testInstance(httpClient: fake);
    await client.init();

    final resp = await client.get('/protected');

    expect(resp.success, true, reason: 'a camelCase refresh must not read as auth-lost');
    expect(client.accessToken, 'new');
  });

  test('refresh sends the key the backend requires', () async {
    final fake = _FakeClient([
      http.Response('{}', 401),
      http.Response(
        jsonEncode({
          'success': true,
          'data': {'accessToken': 'new', 'refreshToken': 'r2'},
        }),
        200,
      ),
      http.Response('{"ok":true}', 200),
    ]);
    final client = ApiClient.testInstance(httpClient: fake);
    await client.init();

    await client.get('/protected');

    final refreshCall = fake.calls.firstWhere(
      (c) => c.url.path.endsWith('/auth/refresh'),
    ) as http.Request;
    final body = jsonDecode(refreshCall.body) as Map<String, dynamic>;

    // The route's zod schema requires refreshToken. Sending only refresh_token
    // was 422'd before reaching the service.
    expect(body['refreshToken'], 'r');
  });

  test('a still-snake_case response keeps working', () async {
    // The backend now answers in both casings, and older deployments answer in
    // neither reliably — so the client must not become strict in the other
    // direction while rolling out.
    final fake = _FakeClient([
      http.Response('{}', 401),
      http.Response(
        jsonEncode({
          'success': true,
          'data': {'access_token': 'new', 'refresh_token': 'r2'},
        }),
        200,
      ),
      http.Response('{"ok":true}', 200),
    ]);
    final client = ApiClient.testInstance(httpClient: fake);
    await client.init();

    final resp = await client.get('/protected');

    expect(resp.success, true);
    expect(client.accessToken, 'new');
  });
}
