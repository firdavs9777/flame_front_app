import 'package:flutter/widgets.dart';
import '../../l10n/gen/app_localizations.dart';

extension L10nX on BuildContext {
  /// Short alias for `AppLocalizations.of(this)` so widgets can read
  /// `context.l10n.welcomeTitle` instead of the verbose form.
  AppLocalizations get l10n => AppLocalizations.of(this);
}
