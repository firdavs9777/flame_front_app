import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/discovery_service.dart';

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

Future<DiscoveryService> _serviceWith(_MockClient mock) async {
  final api = ApiClient.testInstance(httpClient: mock);
  await api.init();
  return DiscoveryService(apiClient: api);
}

http.Response _ok(Map<String, dynamic> data) =>
    http.Response(jsonEncode({'success': true, 'data': data}), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'access_token': 'token', 'refresh_token': 'refresh',
    });
  });

  test('no offset is sent at all', () async {
    final mock = _MockClient(_ok({'users': [], 'pagination': {'has_more': false}}));

    await (await _serviceWith(mock)).getPotentialMatches(limit: 10);

    final url = mock.calls.single.url;
    expect(url.queryParameters['limit'], '10');
    expect(url.queryParameters.containsKey('offset'), isFalse,
        reason: 'the head path is selected by the absence of an offset');
  });

  test('users and hasMore come from the response', () async {
    final mock = _MockClient(_ok({
      'users': [{'id': 'u1', 'name': 'A', 'photos': <dynamic>[]}],
      'pagination': {'has_more': true},
    }));

    final result = await (await _serviceWith(mock)).getPotentialMatches();

    expect(result.data!.users.single.id, 'u1');
    expect(result.data!.hasMore, isTrue);
  });

  test('a missing has_more reads as no more', () async {
    final mock = _MockClient(_ok({'users': []}));

    expect((await (await _serviceWith(mock)).getPotentialMatches()).data!.hasMore,
        isFalse);
  });

  test('a failure surfaces the error', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({'success': false, 'error': {'message': 'nope'}}), 500));

    final result = await (await _serviceWith(mock)).getPotentialMatches();

    expect(result.success, isFalse);
    expect(result.data, isNull);
  });
}
