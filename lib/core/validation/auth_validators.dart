import 'package:flame/l10n/gen/app_localizations.dart';

/// Bounds mirrored from the backend's `registerSchema` (`flame/routes/auth.js:12`).
/// The client must not be stricter or looser than the server, or a user is
/// either blocked from a password the server would accept, or sent to a 422
/// with no field-level message.
const int kMinPasswordLength = 8;
const int kMaxPasswordLength = 128;
const int kMinNameLength = 2;
const int kMaxNameLength = 50;

/// HTML5-style address pattern.
///
/// Replaces `^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$`, which was copy-pasted into three
/// screens and rejected two entirely ordinary things: `\w` excludes `+`, so
/// every Gmail user signing up with plus-addressing was turned away, and
/// `{2,4}` rejects `.museum`, `.travel` and `.online`.
final RegExp kEmailPattern = RegExp(
  r"^[\w.!#$%&'*+/=?^`{|}~-]+"
  r'@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
  r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$',
);

/// Field validation for every auth form, in one place.
///
/// Returns `null` when the value is acceptable and a localized message
/// otherwise — the shape `Form`'s `validator:` expects.
class AuthValidators {
  const AuthValidators(this.l10n);

  final AppLocalizations l10n;

  String? email(String? value) {
    if (value == null || value.isEmpty) return l10n.loginEmailRequired;
    if (!kEmailPattern.hasMatch(value)) return l10n.loginEmailInvalid;
    return null;
  }

  /// For a password being CREATED. Login must use [requiredField] instead —
  /// enforcing a minimum at the door would lock out any existing account whose
  /// password predates the current rule.
  String? password(String? value) {
    if (value == null || value.isEmpty) return l10n.loginPasswordRequired;
    if (value.length < kMinPasswordLength) return l10n.authPasswordTooShort;
    if (value.length > kMaxPasswordLength) return l10n.authPasswordTooLong;
    return null;
  }

  String? confirmPassword(String? value, {required String against}) {
    if (value == null || value.isEmpty) return l10n.authConfirmPasswordRequired;
    if (value != against) return l10n.authPasswordsDoNotMatch;
    return null;
  }

  String? name(String? value) {
    if (value == null || value.isEmpty) return l10n.authNameRequired;
    if (value.length < kMinNameLength) return l10n.authNameTooShort;
    if (value.length > kMaxNameLength) return l10n.authNameTooLong;
    return null;
  }

  /// Presence only, no length rule. Login's password field.
  String? requiredField(String? value) {
    if (value == null || value.isEmpty) return l10n.loginPasswordRequired;
    return null;
  }
}
