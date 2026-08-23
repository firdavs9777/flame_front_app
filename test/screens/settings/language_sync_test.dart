import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flame/services/api_client.dart';
import 'package:flame/services/auth_service.dart';

/// Records the request body so a test can assert the WIRE FORMAT, not just that
/// a call happened. The bug this covers returned 200 and did nothing.
class _RecordingClient extends http.BaseClient {
  final List<Map<String, dynamic>> bodies = [];
  final List<String> paths = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async {
    paths.add(req.url.path);
    if (req is http.Request && req.body.isNotEmpty) {
      bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"success":true,"data":{"locale":"ko"}}')),
      200,
      request: req,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the language sync sends the key the server actually reads', () async {
    // It sent `preferred_language`, which PATCH /users/me does not define. That
    // schema is deliberately not .strict(), so the key was silently STRIPPED:
    // the call returned 200, the app logged nothing, and the server kept the
    // user on English forever. The field is `locale`.
    final client = _RecordingClient();
    final service = AuthService(apiClient: ApiClient.testInstance(httpClient: client));

    await service.updateLocale('ko');

    expect(client.paths.single, endsWith('/users/me'));
    expect(client.bodies.single.keys, ['locale']);
    expect(client.bodies.single['locale'], 'ko');
    expect(client.bodies.single.containsKey('preferred_language'), isFalse,
        reason: 'the server has no such field and silently drops it');
  });

  test('a regional tag goes out in the app tag format', () async {
    // Locale.toLanguageTag() emits 'pt-BR'; config/locales.js enumerates exactly
    // that form, so anything else would 422.
    final client = _RecordingClient();
    final service = AuthService(apiClient: ApiClient.testInstance(httpClient: client));

    await service.updateLocale('pt-BR');

    expect(client.bodies.single['locale'], 'pt-BR');
  });
}
