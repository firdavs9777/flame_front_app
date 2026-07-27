import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/auth_availability_service.dart';

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
    SharedPreferences.setMockInitialValues({});
  });

  test('checkEmail returns success(true) when available', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'success': true,
        'data': {'available': true},
      }),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = AuthAvailabilityService(apiClient: apiClient);

    final result = await service.checkEmail('new@example.com');

    expect(result.success, true);
    expect(result.data, true);

    final req = mock.calls.single as http.Request;
    expect(req.method, 'POST');
    expect(req.url.path.endsWith('/auth/check-email'), true);
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body, {'email': 'new@example.com'});
  });

  test('checkEmail returns success(false) when taken', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'success': true,
        'data': {'available': false},
      }),
      200,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = AuthAvailabilityService(apiClient: apiClient);

    final result = await service.checkEmail('taken@example.com');

    expect(result.success, true);
    expect(result.data, false);
  });

  test('checkEmail surfaces failure on non-200', () async {
    final mock = _MockClient(http.Response(
      jsonEncode({
        'error': {'message': 'boom'},
      }),
      500,
    ));
    final apiClient = _buildApiClient(mock);
    await apiClient.init();
    final service = AuthAvailabilityService(apiClient: apiClient);

    final result = await service.checkEmail('x@example.com');

    expect(result.success, false);
    expect(result.data, isNull);
  });
}
