import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/services/translation_service.dart';

enum TranslationStatus { idle, loading, done, error }

/// Per-message translation state. Cached so a message is only translated once;
/// [visible] lets the user hide/show the translation without re-fetching.
class TranslationEntry {
  final TranslationStatus status;
  final String? text;
  final bool visible;

  const TranslationEntry({
    this.status = TranslationStatus.idle,
    this.text,
    this.visible = false,
  });
}

final translationServiceProvider =
    Provider<TranslationService>((ref) => TranslationService());

class TranslationNotifier extends StateNotifier<Map<String, TranslationEntry>> {
  TranslationNotifier(this._service) : super(const {});

  final TranslationService _service;

  /// Translate [text] of message [messageId] into [targetLang], or toggle the
  /// visibility of an already-fetched translation. Cached results are reused.
  Future<void> toggle({
    required String messageId,
    required String text,
    required String targetLang,
  }) async {
    final current = state[messageId];

    // Already translated → just flip visibility, no re-fetch.
    if (current != null && current.status == TranslationStatus.done) {
      _set(messageId, TranslationEntry(
        status: TranslationStatus.done,
        text: current.text,
        visible: !current.visible,
      ));
      return;
    }

    // A request is already in flight for this message.
    if (current != null && current.status == TranslationStatus.loading) return;

    _set(messageId, const TranslationEntry(
      status: TranslationStatus.loading,
      visible: true,
    ));

    final result = await _service.translate(text: text, targetLang: targetLang);
    if (result.success && result.data != null) {
      _set(messageId, TranslationEntry(
        status: TranslationStatus.done,
        text: result.data,
        visible: true,
      ));
    } else {
      _set(messageId, const TranslationEntry(
        status: TranslationStatus.error,
        visible: true,
      ));
    }
  }

  void _set(String id, TranslationEntry entry) {
    state = {...state, id: entry};
  }
}

final translationProvider =
    StateNotifierProvider<TranslationNotifier, Map<String, TranslationEntry>>(
  (ref) => TranslationNotifier(ref.read(translationServiceProvider)),
);
