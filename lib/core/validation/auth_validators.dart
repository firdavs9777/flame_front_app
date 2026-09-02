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

/// Characters that are invisible in a text field but break an anchored match.
///
/// Dart's `trim()` already removes Unicode whitespace, including the
/// non-breaking space. It does NOT remove the zero-width family, which has no
/// White_Space property — and those ride along on copy-paste from web pages,
/// PDFs and consoles without leaving a trace on screen.
final RegExp _kInvisible = RegExp(r'[\u200B-\u200D\uFEFF]');

/// Normalises an address before it is validated or sent.
///
/// App Review could not sign in with the demo account, and the screenshot
/// showed why: `appreview1@banatalk.com` sitting in the field under the words
/// "Please enter a valid email". The address was correct. What was wrong was
/// invisible — [kEmailPattern] is anchored `^...\$`, so one trailing space
/// carried in from a copy-paste rejects it, and the field looks identical
/// either way.
///
/// Every submit path already trimmed. The VALIDATOR did not, so the form never
/// validated and the button never got the chance to submit anything.
String normalizeEmail(String? raw) =>
    (raw ?? '').replaceAll(_kInvisible, '').trim();

/// Field validation for every auth form, in one place.
///
/// Returns `null` when the value is acceptable and a localized message
/// otherwise — the shape `Form`'s `validator:` expects.
class AuthValidators {
  const AuthValidators(this.l10n);

  final AppLocalizations l10n;

  String? email(String? value) {
    final normalised = normalizeEmail(value);
    if (normalised.isEmpty) return l10n.loginEmailRequired;
    if (!kEmailPattern.hasMatch(normalised)) return l10n.loginEmailInvalid;
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
