/// How two people's declared languages fit together.
///
/// This mirrors `languageScore` in the backend's `rankingService.js`, rung for
/// rung, and that is the whole point of it existing separately. The deck is
/// ordered by the server; this only explains an ordering already decided. If
/// the two ever disagree, the card is not merely unhelpful — it is telling the
/// user a reason that is not the real one. Any change to the server's ladder
/// belongs here in the same breath.
enum LanguageComplement {
  /// Neither side declared enough to say anything. The server scores this
  /// NEUTRAL rather than badly, because every account predates the feature.
  unknown,

  /// Each speaks what the other is learning. The premise of the app, and the
  /// only rung the server scores 1.0.
  mutual,

  /// They speak something the viewer is learning.
  theyTeachYou,

  /// The viewer speaks something they are learning.
  youTeachThem,

  /// A language in common, but neither is teaching the other.
  shared,

  /// Declared, and nothing lines up.
  none,
}

/// Classifies [their] languages against the viewer's.
///
/// Codes are compared case-insensitively and blanks ignored, because these
/// arrive from a server that has stored them since before validation existed.
LanguageComplement languageComplement({
  required List<String> viewerSpoken,
  required List<String> viewerLearning,
  required List<String> theirSpoken,
  required List<String> theirLearning,
}) {
  final mySpoken = _codes(viewerSpoken);
  final myLearning = _codes(viewerLearning);
  final ourSpoken = _codes(theirSpoken);
  final ourLearning = _codes(theirLearning);

  // Matches the server's first guard: silence is not a poor match, it is no
  // information. Saying anything at all here would be inventing a reason.
  if (mySpoken.isEmpty || ourSpoken.isEmpty) return LanguageComplement.unknown;

  final theyTeachMe = ourSpoken.intersection(myLearning).isNotEmpty;
  final iTeachThem = mySpoken.intersection(ourLearning).isNotEmpty;

  if (theyTeachMe && iTeachThem) return LanguageComplement.mutual;
  if (theyTeachMe) return LanguageComplement.theyTeachYou;
  if (iTeachThem) return LanguageComplement.youTeachThem;
  if (mySpoken.intersection(ourSpoken).isNotEmpty) {
    return LanguageComplement.shared;
  }
  return LanguageComplement.none;
}

Set<String> _codes(List<String> raw) => raw
    .map((c) => c.trim().toLowerCase())
    .where((c) => c.isNotEmpty)
    .toSet();
