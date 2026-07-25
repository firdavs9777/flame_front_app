import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/translation_service.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.response);
  final http.Response response;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async {
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
      request: req,
    );
  }
}

TranslationService _serviceReturning(http.Response response) {
  final api = ApiClient.testInstance(httpClient: _FakeClient(response));
  return TranslationService(apiClient: api);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('returns translated text from the data envelope', () async {
    final service =
        _serviceReturning(http.Response('{"data":{"translated_text":"Hello"}}', 200));
    final result = await service.translate(text: 'Hola', targetLang: 'en');
    expect(result.success, isTrue);
    expect(result.data, 'Hello');
  });

  test('accepts a bare "translation" key', () async {
    final service =
        _serviceReturning(http.Response('{"translation":"Bonjour"}', 200));
    final result = await service.translate(text: 'Hi', targetLang: 'fr');
    expect(result.success, isTrue);
    expect(result.data, 'Bonjour');
  });

  test('fails gracefully when the endpoint is missing (404)', () async {
    final service = _serviceReturning(http.Response('{"success":false}', 404));
    final result = await service.translate(text: 'Hola', targetLang: 'en');
    expect(result.success, isFalse);
  });

  test('does not hit the network for empty text', () async {
    final service = _serviceReturning(http.Response('{}', 200));
    final result = await service.translate(text: '   ', targetLang: 'en');
    expect(result.success, isFalse);
    expect(result.error, isNotNull);
  });
}
