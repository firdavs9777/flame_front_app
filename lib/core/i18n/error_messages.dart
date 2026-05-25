import '../../l10n/gen/app_localizations.dart';
import '../../services/api_client.dart';

/// Maps an [ApiResponse] error to a localized user-facing string.
///
/// The backend returns stable `errorCode` values; this is the single place
/// the client decides which translation key to show. Unknown codes fall back
/// to the backend's English [ApiResponse.error] message, or — if even that
/// is missing — to a generic fallback.
String translateApiError(AppLocalizations l10n, ApiResponse response) {
  switch (response.errorCode) {
    case 'INVALID_CREDENTIALS':
      return l10n.errorInvalidCredentials;
    case 'EMAIL_EXISTS':
      return l10n.errorEmailExists;
    case 'RATE_LIMITED':
      return l10n.errorRateLimited;
    case 'AUTH_LOST':
      return l10n.errorAuthLost;
  }
  return response.error ?? l10n.errorGeneric;
}
