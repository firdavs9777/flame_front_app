/// Whether an incoming chat message should default to showing its
/// translation, rather than requiring a tap.
///
/// True only for a KNOWN mismatch: both people have declared at least one
/// spoken language, and those sets share none. Unknown must never force
/// translation on — a missing declaration is not evidence of a language
/// gap, and defaulting on for two people who in fact share a language would
/// be a visible regression, not a feature. This is why the guard is on
/// EMPTY, not on absence of overlap alone.
bool shouldDefaultTranslationOn({
  required List<String> viewerSpoken,
  required List<String> partnerSpoken,
}) {
  if (viewerSpoken.isEmpty || partnerSpoken.isEmpty) return false;

  final viewer = viewerSpoken.map((c) => c.toLowerCase()).toSet();
  final partner = partnerSpoken.map((c) => c.toLowerCase()).toSet();

  return viewer.intersection(partner).isEmpty;
}
