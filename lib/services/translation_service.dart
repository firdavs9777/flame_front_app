import 'package:flame/services/api_client.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

/// Translates chat message text via the backend.
///
/// Posts to `/translate` following the app's [ApiClient]/[ServiceResult]
/// conventions. The backend (or a provider behind it) is the source of truth
/// for the actual translation; this service is only the client seam, so the
/// translation provider can be swapped without touching the UI.
class TranslationService {
  TranslationService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  /// Translate [text] into [targetLang] (an ISO code like `ja`, `es`).
  /// [sourceLang] is optional — omit to let the backend auto-detect.
  Future<ServiceResult<String>> translate({
    required String text,
    required String targetLang,
    String? sourceLang,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return ServiceResult.failure('Nothing to translate');
    }

    final response = await _apiClient.post('/translate', body: {
      'text': trimmed,
      'target_lang': targetLang,
      if (sourceLang != null) 'source_lang': sourceLang,
    });

    if (response.success && response.data != null) {
      final data = response.data;
      final translated = _extractTranslation(data);
      if (translated != null && translated.isNotEmpty) {
        return ServiceResult.success(translated);
      }
      return ServiceResult.failure('Translation unavailable');
    }

    return ServiceResult.failure(response.error ?? 'Translation failed');
  }

  /// Accept the common response shapes so the UI keeps working regardless of
  /// the exact key the backend settles on.
  String? _extractTranslation(dynamic data) {
    if (data is Map) {
      final value = data['translated_text'] ?? data['translation'] ?? data['text'];
      if (value is String) return value;
    }
    if (data is String) return data;
    return null;
  }
}
