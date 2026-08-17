/// Renders a stored distance preference for display without discarding
/// precision.
///
/// Returns the number only, with no unit, so callers can append whatever
/// suffix their layout wants. A whole number prints without a trailing `.0`;
/// anything else prints as Dart's own shortest round-tripping decimal.
///
/// Lives here rather than in either screen because both the editor and the
/// read-only profile render the same stored value, and they disagreed: the
/// editor stopped rounding deliberately, while the profile used
/// `.toInt()` and truncated, so a stored 24.6 read as "24 km" on one screen
/// and "24.6" on the other.
///
/// Rounding or truncating is not a display-only choice here: the editor seeds
/// its text field from this, so `.round()` would silently rewrite a stored
/// 24.6 to 25 the next time the section saves, even if the user never touched
/// the field.
String formatDistance(double value) {
  if (value == value.truncateToDouble()) {
    return value.truncate().toString();
  }
  return value.toString();
}
