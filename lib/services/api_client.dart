import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  // Auto-detect platform for correct localhost URL
  // For real device, change this to your computer's IP: http://192.168.x.x:8000/v1
  static String get baseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8000/v1'; // Android emulator
    }
    return 'http://127.0.0.1:8000/v1'; // iOS simulator / desktop
  }

  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userIdKey = 'user_id';

  String? _accessToken;
  String? _refreshToken;
  String? _userId;

  // Singleton pattern
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

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

      final response = await http.get(uri, headers: _headers).timeout(
        const Duration(seconds: 30),
      );
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
      final response = await http.post(
        uri,
        headers: _headers,
        body: body != null ? jsonEncode(body) : null,
      ).timeout(const Duration(seconds: 30));
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
      final response = await http.patch(
        uri,
        headers: _headers,
        body: body != null ? jsonEncode(body) : null,
      ).timeout(const Duration(seconds: 30));
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
  Future<ApiResponse> delete(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final request = http.Request('DELETE', uri);
      request.headers.addAll(_headers);
      if (body != null) {
        request.body = jsonEncode(body);
      }
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
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

    try {
      if (response.body.isNotEmpty) {
        data = jsonDecode(response.body);
      }
    } catch (_) {
      // Response is not JSON
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
      }

      return ApiResponse(
        success: false,
        data: data,
        error: errorMessage,
        errorCode: errorCode,
        statusCode: statusCode,
      );
    }
  }

  // Refresh token
  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      final uri = Uri.parse('$baseUrl/auth/refresh');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': _refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final tokenData = data['data'] ?? data;
        await saveTokens(
          accessToken: tokenData['access_token'],
          refreshToken: tokenData['refresh_token'],
        );
        return true;
      }
    } catch (_) {}

    return false;
  }
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
