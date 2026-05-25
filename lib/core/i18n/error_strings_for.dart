import '../../l10n/gen/app_localizations.dart';
import '../../services/api_client.dart';
import 'error_messages.dart';

/// Provider-friendly wrapper around translateApiError. Providers don't have
/// BuildContext, so we cache the current AppLocalizations at startup and on
/// every MaterialApp rebuild (locale changes trigger a rebuild).
class ErrorStringsFor {
  static AppLocalizations? _cached;

  static void prime(AppLocalizations l) {
    _cached = l;
  }

  /// Translate an [ApiResponse] error to a localized string.
  static String message(ApiResponse r) {
    final l10n = _cached;
    if (l10n == null) return r.error ?? 'Error';
    return translateApiError(l10n, r);
  }

  /// Convenience method for call sites that hold a raw error [String?] (e.g.
  /// from ServiceResult.error) and have no errorCode to switch on.
  static String fromString(String? error) {
    final l10n = _cached;
    if (l10n == null) return error ?? 'Error';
    return error ?? l10n.errorGeneric;
  }
}
