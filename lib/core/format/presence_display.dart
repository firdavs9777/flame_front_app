import 'package:flame/l10n/gen/app_localizations.dart';

/// "Online" / "Just now" / "5m ago" — how recently someone was here.
///
/// One implementation, because there were three: `User.lastActiveText`,
/// `OnlineStatusIndicator._statusText`, and the inline check on the profile
/// card. All three were English-only, and they disagreed — one said "Long time
/// ago" past a week, another "Long ago", and the third had no under-a-minute
/// case at all, so a user seen forty seconds ago read as "0m ago".
///
/// [now] is injectable so a test can pin the clock instead of racing it.
String presenceText({
  required bool isOnline,
  required DateTime? lastSeen,
  required AppLocalizations l10n,
  DateTime? now,
}) {
  if (isOnline) return l10n.presenceOnline;
  if (lastSeen == null) return l10n.presenceOffline;

  final diff = (now ?? DateTime.now()).difference(lastSeen);

  // A clock skewed into the future would otherwise render "-3m ago".
  if (diff.isNegative || diff.inMinutes < 1) return l10n.presenceJustNow;
  if (diff.inMinutes < 60) return l10n.presenceMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.presenceHoursAgo(diff.inHours);
  if (diff.inDays < 7) return l10n.presenceDaysAgo(diff.inDays);
  return l10n.presenceLongAgo;
}
