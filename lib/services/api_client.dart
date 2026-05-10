import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
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

  // Mutex completer that serializes concurrent refresh attempts. When non-null
  // a refresh is already in flight; followers await the same future.
  Completer<void>? _refreshing;

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
    } on SocketException {
      return ApiResponse.error('No internet connection');
    } on HttpException {
      return ApiResponse.error('Server error');
    } catch (e) {
      return ApiResponse.error(e.toString());
    }
  }

  // Wraps an HTTP operation so a single 401 triggers a single shared refresh
  // across concurrent in-flight calls. On successful refresh the operation is
  // retried once; the underlying op closure re-reads `_headers` so the new
  // access token is picked up on retry.
  Future<http.Response> _authenticated(
      Future<http.Response> Function(http.Client) op) async {
    var resp = await op(_httpClient);
    if (resp.statusCode == 401 && !_isRefreshUrl(resp)) {
      final existing = _refreshing;
      final isLeader = existing == null;
      final mutex = isLeader ? (_refreshing = Completer<void>()) : existing;
      if (isLeader) {
        try {
          final ok = await _doRefresh();
          if (!ok) {
            mutex.completeError(_AuthLost());
            throw _AuthLost();
          }
          mutex.complete();
        } catch (e) {
          if (!mutex.isCompleted) mutex.completeError(e);
          rethrow;
        } finally {
          if (identical(_refreshing, mutex)) _refreshing = null;
        }
      } else {
        await mutex.future;
      }
      resp = await op(_httpClient);
    }
    return resp;
  }

  bool _isRefreshUrl(http.Response resp) {
    final p = resp.request?.url.path ?? '';
    return p.endsWith('/auth/refresh');
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
    String method = 'POST',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final request = http.MultipartRequest(method, uri);

      // Add auth header
      if (_accessToken != null) {
        request.headers['Authorization'] = 'Bearer $_accessToken';
      }

      request.files.add(await http.MultipartFile.fromPath(fieldName, file.path));

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
          errorMessage = data['detail'];
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
