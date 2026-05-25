import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/error_messages.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/services/api_client.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('maps INVALID_CREDENTIALS to localized string', () {
    final r = ApiResponse(success: false, errorCode: 'INVALID_CREDENTIALS', statusCode: 401);
    expect(translateApiError(l10n, r), 'Incorrect email or password.');
  });

  test('maps RATE_LIMITED to localized string', () {
    final r = ApiResponse(success: false, errorCode: 'RATE_LIMITED', statusCode: 429);
    expect(translateApiError(l10n, r), contains('too often'));
  });

  test('maps AUTH_LOST to localized string', () {
    final r = ApiResponse(success: false, errorCode: 'AUTH_LOST', statusCode: 401);
    expect(translateApiError(l10n, r), contains('session has ended'));
  });

  test('unknown errorCode falls back to backend error string', () {
    final r = ApiResponse(
      success: false,
      errorCode: 'SOMETHING_NEW',
      error: 'Backend said this',
      statusCode: 400,
    );
    expect(translateApiError(l10n, r), 'Backend said this');
  });

  test('unknown errorCode with no error string falls back to generic', () {
    final r = ApiResponse(success: false, errorCode: 'WHATEVER', statusCode: 500);
    expect(translateApiError(l10n, r), 'Something went wrong. Please try again.');
  });

  test('null errorCode with backend message uses backend message', () {
    final r = ApiResponse(success: false, error: 'Network blip', statusCode: 0);
    expect(translateApiError(l10n, r), 'Network blip');
  });
}
