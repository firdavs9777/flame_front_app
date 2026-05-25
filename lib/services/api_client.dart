import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/env.dart';

class ApiClient {
  static String get baseUrl => EnvConfig.current.apiBase;

  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userIdKey = 'user_id';

  String? _accessToken;
  String? _refreshToken;
  String? _userId;

  // Injected http client (for test injection). In production uses default http.Client.
  final http.Client _httpClient;

  // Singleflight mutex for concurrent refresh attempts. When non-null a
  // refresh is already in flight; followers await the same future. The bool
  // value is the refresh outcome (true = success). We deliberately don't use
  // completeError here — unobserved error futures get reported as unhandled
  // exceptions when no follower happens to be awaiting.
  Completer<bool>? _refreshing;

  // Registered by AuthNotifier so that when ApiClient detects the session is
  // gone (refresh failed, token revoked, session expired), the UI can react
  // immediately — clear local state, route to login. Without this callback,
  // the user would only discover they're logged out on their next manual
  // navigation.
  Future<void> Function()? onAuthLost;

  // Singleton pattern
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal() : _httpClient = http.Client();

  // Test-only constructor: builds an isolated instance with an injected HTTP
  // client. Does NOT share state with the singleton.
  ApiClient.testInstance({required http.Client httpClient})
      : _httpClient = httpClient;

  // Initialize tokens from storage
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessTokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    _userId = prefs.getString(_userIdKey);
  }

  // Save tokens to storage
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    String? userId,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    if (userId != null) _userId = userId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, accessToken);
    await prefs.setString(_refreshTokenKey, refreshToken);
    if (userId != null) await prefs.setString(_userIdKey, userId);
  }

  // Clear tokens
  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _userId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userIdKey);
  }

  // Check if user has tokens
  bool get hasTokens => _accessToken != null;
  String? get accessToken => _accessToken;
  String? get userId => _userId;

  // Headers
  Map<String, String> get _headers {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  // GET request
  Future<ApiResponse> get(String endpoint, {Map<String, String>? queryParams}) async {
    try {
      var uri = Uri.parse('$baseUrl$endpoint');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }

      final response = await _authenticated((c) =>
          c.get(uri, headers: _headers).timeout(const Duration(seconds: 30)));
      return _handleResponse(response);
    } on _AuthLost {
      return await _onAuthLost();
    } on SocketException {
      return ApiResponse.error('No internet connection');
    } on HttpException {
      return ApiResponse.error('Server error');
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }

  // POST request
  Future<ApiResponse> post(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final response = await _authenticated((c) => c
          .post(
            uri,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30)));
      return _handleResponse(response);
    } on _AuthLost {
      return await _onAuthLost();
    } on SocketException {
      return ApiResponse.error('No internet connection');
    } on HttpException {
      return ApiResponse.error('Server error');
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }

  // PATCH request
  Future<ApiResponse> patch(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final response = await _authenticated((c) => c
          .patch(
            uri,
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30)));
      return _handleResponse(response);
    } on _AuthLost {
      return await _onAuthLost();
    } on SocketException {
      return ApiResponse.error('No internet connection');
    } on HttpException {
      return ApiResponse.error('Server error');
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }

  // DELETE request
  Future<ApiResponse> delete(String endpoint, {Map<String, dynamic>? body, Map<String, String>? queryParams}) async {
    try {
      var uri = Uri.parse('$baseUrl$endpoint');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }
      final response = await _authenticated((c) async {
        final request = http.Request('DELETE', uri);
        request.headers.addAll(_headers);
        if (body != null) {
          request.body = jsonEncode(body);
        }
        final streamedResponse =
            await c.send(request).timeout(const Duration(seconds: 30));
        return http.Response.fromStream(streamedResponse);
      });
      return _handleResponse(response);
    } on _AuthLost {
      return await _onAuthLost();
    } on SocketException {
      return ApiResponse.error('No internet connection');
    } on HttpException {
      return ApiResponse.error('Server error');
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }

  // Single point that handles a lost session: clears local tokens, notifies
  // the app (so AuthNotifier can flip to unauthenticated and route to login),
  // and returns a clean user-facing error. Idempotent and safe to call from
  // every public method's _AuthLost catch.
  Future<ApiResponse> _onAuthLost() async {
    await clearTokens();
    try {
      await onAuthLost?.call();
    } catch (_) {
      // Don't let a listener exception mask the auth-lost outcome.
    }
    return ApiResponse(
      success: false,
      error: 'Auth lost',
      errorCode: 'AUTH_LOST',
      statusCode: 401,
    );
  }

  // Wraps an HTTP operation with two behaviors:
  // 1. Proactive refresh: if the access token's JWT exp claim is within
  //    _proactiveRefreshWindow, refresh before sending. Keeps mid-session
  //    requests from getting unexpected 401s when tokens expire at 15 min.
  // 2. Reactive refresh: a single 401 triggers a single shared refresh across
  //    concurrent in-flight calls. On successful refresh the op is retried
  //    once; the closure re-reads `_headers` so the new token is picked up.
  //    If the 401 is a deliberate revoke/expiry (logout from another device,
  //    explicit revoke), skip the refresh attempt and surface _AuthLost so
  //    the app forces re-login.
  static const Duration _proactiveRefreshWindow = Duration(seconds: 120);

  Future<http.Response> _authenticated(
      Future<http.Response> Function(http.Client) op) async {
    if (_shouldProactivelyRefresh()) {
      // Best-effort proactive refresh. If it fails (e.g., flaky network,
      // refresh token actually invalid), fall through to the request — the
      // reactive 401 path below will catch real auth failures cleanly.
      try {
        await _runRefreshThroughMutex();
      } catch (_) {}
    }
    var resp = await op(_httpClient);
    if (resp.statusCode == 401 && !_isRefreshUrl(resp)) {
      // No access token means this 401 came from an unauthenticated request
      // — login, register, social sign-in — where there's no session to lose
      // and nothing to refresh. Pass the response through so the caller sees
      // the backend's real error (e.g. "Invalid Google token") instead of
      // our generic "session ended" message.
      if (_accessToken == null) {
        return resp;
      }
      if (_isRevokedTokenResponse(resp)) {
        throw _AuthLost();
      }
      await _runRefreshThroughMutex();
      resp = await op(_httpClient);
    }
    return resp;
  }

  // Run _doRefresh through the singleflight mutex. Concurrent callers await
  // the same in-flight refresh; the leader performs the work, completes the
  // shared future with the outcome, and (if failure) throws so the caller's
  // error path runs. We never call completeError on the mutex — followers
  // read the bool result and throw themselves on failure.
  Future<void> _runRefreshThroughMutex() async {
    final existing = _refreshing;
    final isLeader = existing == null;
    final mutex = isLeader ? (_refreshing = Completer<bool>()) : existing;
    if (isLeader) {
      var ok = false;
      try {
        ok = await _doRefresh();
      } catch (_) {
        ok = false;
      } finally {
        if (identical(_refreshing, mutex)) _refreshing = null;
        if (!mutex.isCompleted) mutex.complete(ok);
      }
      if (!ok) throw _AuthLost();
    } else {
      final ok = await mutex.future;
      if (!ok) throw _AuthLost();
    }
  }

  bool _isRefreshUrl(http.Response resp) {
    final p = resp.request?.url.path ?? '';
    return p.endsWith('/auth/refresh');
  }

  // Returns true if the access token's exp claim is within
  // _proactiveRefreshWindow of now. Returns false if no token, no refresh
  // token, malformed JWT, missing exp, or a refresh is already in flight.
  bool _shouldProactivelyRefresh() {
    if (_accessToken == null || _refreshToken == null) return false;
    if (_refreshing != null) return false;
    final remaining = _accessTokenLifetimeRemaining();
    if (remaining == null) return false;
    return remaining <= _proactiveRefreshWindow;
  }

  // Decode the JWT exp claim and return how much lifetime is left. Returns
  // null on any parse failure or missing exp — caller should treat null as
  // "don't refresh proactively, let the reactive 401 path handle it."
  Duration? _accessTokenLifetimeRemaining() {
    final token = _accessToken;
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payloadStr =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! int) return null;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return expiresAt.difference(DateTime.now());
    } catch (_) {
      return null;
    }
  }

  // Detects 401 responses that mean "this session is dead, don't bother
  // refreshing." Matched against backend messages like "Token revoked" and
  // "Session expired, please log in again."
  bool _isRevokedTokenResponse(http.Response resp) {
    if (resp.body.isEmpty) return false;
    try {
      final data = jsonDecode(resp.body);
      if (data is! Map<String, dynamic>) return false;
      final message = _extractErrorMessage(data)?.toLowerCase();
      if (message == null) return false;
      return message.contains('revoked') ||
          (message.contains('session') && message.contains('expired'));
    } catch (_) {
      return false;
    }
  }

  // Extract a user-readable error message from common backend error shapes.
  // Mirrors the parsing in _handleResponse so both stay in sync.
  String? _extractErrorMessage(Map<String, dynamic> data) {
    final err = data['error'];
    if (err is Map && err['message'] is String) return err['message'] as String;
    if (err is String) return err;
    final detail = data['detail'];
    if (detail is Map && detail['message'] is String) {
      return detail['message'] as String;
    }
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty && detail.first is Map) {
      final msg = (detail.first as Map)['msg'];
      if (msg is String) return msg;
    }
    final message = data['message'];
    if (message is String) return message;
    return null;
  }

  // Performs the refresh through the injected HTTP client so tests can
  // observe and assert on the call.
  Future<bool> _doRefresh() async {
    if (_refreshToken == null) return false;
    try {
      final resp = await _httpClient.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      );
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body);
      final tokenData = data['data'] ?? data;
      await saveTokens(
        accessToken: tokenData['access_token'],
        refreshToken: tokenData['refresh_token'],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // Multipart request for file uploads
  Future<ApiResponse> uploadFile(
    String endpoint,
    File file, {
    String fieldName = 'photo',
    Map<String, String>? fields,
    Map<String, String>? queryParams,
    String method = 'POST',
  }) async {
    try {
      var uri = Uri.parse('$baseUrl$endpoint');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }
      final request = http.MultipartRequest(method, uri);

      // Add auth header
      if (_accessToken != null) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
      }

      request.files.add(await http.MultipartFile.fromPath(
        fieldName,
        file.path,
        contentType: _mimeTypeForFile(file.path),
      ));

      if (fields != null) {
        request.fields.addAll(fields);
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse(response);
    } on SocketException {
      return ApiResponse.error('No internet connection');
    } on HttpException {
      return ApiResponse.error('Server error');
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }

  MediaType _mimeTypeForFile(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      default:
        return MediaType('image', 'jpeg');
    }
  }

  // Handle response
  ApiResponse _handleResponse(http.Response response) {
    final statusCode = response.statusCode;
    Map<String, dynamic>? data;

    // Debug logging
    print('API Response [${response.request?.method} ${response.request?.url}]: $statusCode');

    try {
      if (response.body.isNotEmpty) {
        data = jsonDecode(response.body);
        print('API Response Body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');
      }
    } catch (e) {
      // Response is not JSON
      print('API Response (non-JSON): ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}');
    }

    if (statusCode >= 200 && statusCode < 300) {
      return ApiResponse(
        success: data?['success'] ?? true,
        data: data?['data'] ?? data,
        message: data?['message'],
        statusCode: statusCode,
      );
    } else if (statusCode == 429) {
      // Rate limited. Surface only errorCode — UI translates via
      // translateApiError(). Retry-after preserved in error string for any
      // log/diagnostic display.
      final retryAfter = response.headers['retry-after'];
      final retryHint = retryAfter != null ? ' (retry-after: ${retryAfter}s)' : '';
      return ApiResponse(
        success: false,
        data: data,
        error: 'Rate limited$retryHint',
        errorCode: 'RATE_LIMITED',
        statusCode: statusCode,
      );
    } else {
      String errorMessage = 'Something went wrong';
      String? errorCode;

      if (data != null) {
        if (data['error'] is Map) {
          errorMessage = data['error']['message'] ?? errorMessage;
          errorCode = data['error']['code'];
        } else if (data['error'] is String) {
          errorMessage = data['error'];
        } else if (data['detail'] != null) {
          final detail = data['detail'];
          if (detail is Map) {
            // App exception: {"code": "EMAIL_EXISTS", "message": "..."}
            errorMessage = detail['message'] ?? errorMessage;
            errorCode = detail['code']?.toString();
          } else if (detail is List && detail.isNotEmpty) {
            // Pydantic validation error: [{"type": "...", "msg": "..."}]
            final first = detail[0];
            if (first is Map) {
              String msg = first['msg']?.toString() ?? errorMessage;
              // Strip Pydantic's "Value error, " prefix
              if (msg.startsWith('Value error, ')) {
                msg = msg.substring('Value error, '.length);
              }
              errorMessage = msg;
            }
          }
        } else if (data['message'] != null) {
          errorMessage = data['message'];
        }
      } else {
        // If no parsed data, use status code description
        errorMessage = _getStatusCodeMessage(statusCode);
      }

      print('API Error: $statusCode - $errorMessage');

      return ApiResponse(
        success: false,
        data: data,
        error: '$errorMessage (Status: $statusCode)',
        errorCode: errorCode,
        statusCode: statusCode,
      );
    }
  }

  String _getStatusCodeMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Bad request';
      case 401:
        return 'Unauthorized - Please login again';
      case 403:
        return 'Access forbidden';
      case 404:
        return 'Not found';
      case 422:
        return 'Validation error';
      case 500:
        return 'Server error - Please try again later';
      case 502:
        return 'Server is temporarily unavailable';
      case 503:
        return 'Service unavailable';
      default:
        return 'Error occurred';
    }
  }

  // Refresh token (kept as public API for callers that drive refresh
  // explicitly; routes through the same internal helper as the 401 mutex).
  Future<bool> refreshAccessToken() => _doRefresh();
}

class _AuthLost implements Exception {
  @override
  String toString() => 'AuthLost: refresh failed';
}

class ApiResponse {
  final bool success;
  final dynamic data;
  final String? message;
  final String? error;
  final String? errorCode;
  final int statusCode;

  ApiResponse({
    required this.success,
    this.data,
    this.message,
    this.error,
    this.errorCode,
    this.statusCode = 0,
  });

  factory ApiResponse.error(String message) {
    return ApiResponse(
      success: false,
      error: message,
      statusCode: 0,
    );
  }

  @override
  String toString() {
    return 'ApiResponse(success: $success, statusCode: $statusCode, error: $error, errorCode: $errorCode)';
  }
}
