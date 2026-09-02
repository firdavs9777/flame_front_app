import 'package:flutter/foundation.dart';

import 'package:flame/core/languages/language_flags.dart';

/// One language, as served by `GET /flamebackend/v1/languages`.
///
/// Mirrors BananaTalk's `models/language_model.dart` so the two products
/// describe the same thing the same way.
@immutable
class Language {
  const Language({
    required this.code,
    required this.name,
    required this.nativeName,
  });

  /// ISO 639-1, lowercase. The stored value, never translated — translating a
  /// stored value breaks every record and every match at once.
  final String code;

  /// The English name. Used for SEARCH, so someone can type "Korean" as well
  /// as 한국어.
  final String name;

  /// The language's own name — what the picker and profiles display.
  final String nativeName;

  /// Country flag, or 🌐 when none is defensible.
  String get flag => LanguageFlags.getFlag(code);

  factory Language.fromJson(Map<String, dynamic> json) {
    final code = (json['code'] as String?)?.trim();
    if (code == null || code.isEmpty) {
      throw ArgumentError('language entry has no code: $json');
    }
    // Blank is treated exactly like absent, for every field a reader may
    // index or uppercase. The served catalogue has rows with `"name": ""`,
    // and those parsed fine and then threw a RangeError on `name[0]` in the
    // picker's A-Z sectioning -- a red screen the catalogue fallback cannot
    // rescue, because the row itself parsed.
    final trimmedName = (json['name'] as String?)?.trim();
    final name = (trimmedName == null || trimmedName.isEmpty) ? code : trimmedName;
    final native = (json['nativeName'] as String?)?.trim();

    return Language(
      code: code.toLowerCase(),
      name: name,
      // An empty nativeName is real in the backend data. A blank row in a
      // picker is worse than an English one.
      nativeName: (native == null || native.isEmpty) ? name : native,
    );
  }

  @override
  bool operator ==(Object other) => other is Language && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
