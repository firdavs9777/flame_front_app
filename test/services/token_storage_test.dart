import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/services/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  http.Client _noNet() =>
      MockClient((req) async => http.Response('{}', 200));

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('saveTokens persists to secure storage and reloads via init', () async {
    final a = ApiClient.testInstance(httpClient: _noNet());
    await a.saveTokens(accessToken: 'AT', refreshToken: 'RT', userId: 'u1');

    final b = ApiClient.testInstance(httpClient: _noNet());
    await b.init();
    expect(b.accessToken, 'AT');
    expect(b.hasTokens, isTrue);
  });

  test('migrates legacy SharedPreferences tokens on init, then clears prefs', () async {
    SharedPreferences.setMockInitialValues({
      'access_token': 'LEGACY_AT',
      'refresh_token': 'LEGACY_RT',
      'user_id': 'legacyUser',
    });
    final a = ApiClient.testInstance(httpClient: _noNet());
    await a.init();
    expect(a.accessToken, 'LEGACY_AT');

    // Legacy prefs are purged after migration.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), isNull);

    // And they now live in secure storage.
    const secure = FlutterSecureStorage();
    expect(await secure.read(key: 'access_token'), 'LEGACY_AT');
  });

  test('clearTokens removes tokens from secure storage', () async {
    final a = ApiClient.testInstance(httpClient: _noNet());
    await a.saveTokens(accessToken: 'AT', refreshToken: 'RT');
    await a.clearTokens();
    expect(a.hasTokens, isFalse);
    const secure = FlutterSecureStorage();
    expect(await secure.read(key: 'access_token'), isNull);
  });
}
