import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/translation_service.dart';
import 'package:flame/providers/translation_provider.dart';

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

TranslationNotifier _notifierReturning(http.Response response) {
  final api = ApiClient.testInstance(httpClient: _FakeClient(response));
  return TranslationNotifier(TranslationService(apiClient: api));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stores a translation and marks it visible on success', () async {
    final notifier =
        _notifierReturning(http.Response('{"data":{"translated_text":"Hello"}}', 200));

    await notifier.toggle(messageId: 'm1', text: 'Hola', targetLang: 'en');

    final entry = notifier.state['m1']!;
    expect(entry.status, TranslationStatus.done);
    expect(entry.text, 'Hello');
    expect(entry.visible, isTrue);
  });

  test('toggling a translated message flips visibility without refetching',
      () async {
    final notifier =
        _notifierReturning(http.Response('{"data":{"translated_text":"Hello"}}', 200));

    await notifier.toggle(messageId: 'm1', text: 'Hola', targetLang: 'en');
    await notifier.toggle(messageId: 'm1', text: 'Hola', targetLang: 'en');

    final entry = notifier.state['m1']!;
    expect(entry.status, TranslationStatus.done);
    expect(entry.text, 'Hello'); // still cached
    expect(entry.visible, isFalse); // hidden now
  });

  test('records an error state when translation fails', () async {
    final notifier = _notifierReturning(http.Response('{"success":false}', 404));

    await notifier.toggle(messageId: 'm2', text: 'Hola', targetLang: 'en');

    expect(notifier.state['m2']!.status, TranslationStatus.error);
  });
}
