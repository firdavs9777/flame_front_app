import 'package:flame/core/languages/language.dart';
import 'package:flame/core/languages/language_fallback.dart';

/// The display name for [code], given whatever catalogue is loaded.
///
/// Falls through the loaded catalogue, then the bundled fallback, then the
/// raw code — mirroring BananaTalk's getLanguageName, which degrades to the
/// code rather than throwing. A code can arrive from a newer client or survive
/// a catalogue edit, and rendering "zz" on a profile is a blemish where
/// crashing the profile is a bug.
String languageLabel(String code, List<Language> catalog) {
  final lower = code.toLowerCase();
  for (final l in catalog) {
    if (l.code == lower) return l.nativeName;
  }
  for (final l in kLanguageFallback) {
    if (l.code == lower) return l.nativeName;
  }
  return code;
}
