import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/languages/language.dart';
import 'package:flame/core/languages/language_fallback.dart';
import 'package:flame/core/languages/language_flags.dart';

void main() {
  group('Language.fromJson', () {
    test('parses the GET /languages shape', () {
      final l = Language.fromJson({
        'code': 'ko', 'name': 'Korean', 'nativeName': '한국어',
      });

      expect(l.code, 'ko');
      expect(l.name, 'Korean');
      expect(l.nativeName, '한국어');
    });

    test('falls back to the English name when nativeName is missing', () {
      // The backend has entries with an empty nativeName. A blank label in a
      // picker is worse than an English one.
      final l = Language.fromJson({'code': 'xx', 'name': 'Example'});
      expect(l.nativeName, 'Example');
    });

    test('an empty name falls back to the code, like a missing one', () {
      // A served row with "name": "" used to sail through fromJson and then
      // blow up in the picker on name[0]. Empty and absent are the same
      // thing to every reader of this field.
      final l = Language.fromJson({'code': 'xx', 'name': ''});
      expect(l.name, 'xx');
      expect(l.nativeName, 'xx');
    });

    test('a whitespace-only name falls back to the code', () {
      final l = Language.fromJson({'code': 'yy', 'name': '   '});
      expect(l.name, 'yy');
      expect(l.nativeName, 'yy');
    });

    test('a whitespace-only nativeName falls back to the name', () {
      final l = Language.fromJson({
        'code': 'zz', 'name': 'Example', 'nativeName': '  ',
      });
      expect(l.nativeName, 'Example');
    });

    test('a malformed entry throws rather than becoming a blank row', () {
      expect(() => Language.fromJson({'name': 'No code'}), throwsA(anything));
    });
  });

  group('flags', () {
    test('English is 🇬🇧, matching the BananaTalk map', () {
      // NOT 🇺🇸. Mirrored deliberately so the two products agree.
      expect(LanguageFlags.getFlag('en'), '🇬🇧');
    });

    test('regional variants resolve before the base language', () {
      expect(LanguageFlags.getFlag('en-us'), '🇺🇸');
      expect(LanguageFlags.getFlag('en-gb'), '🇬🇧');
    });

    test('an unknown region falls back to the base language', () {
      expect(LanguageFlags.getFlag('es-cl'), LanguageFlags.getFlag('es'));
    });

    test('anything unrecognised is the globe, never a wrong flag', () {
      expect(LanguageFlags.getFlag('zz'), '🌐');
      expect(LanguageFlags.getFlag(''), '🌐');
    });
  });

  group('offline fallback', () {
    test('is small but never empty', () {
      // The picker must work on a first-ever launch with no network. This is
      // the floor, not the catalogue.
      expect(kLanguageFallback, isNotEmpty);
      expect(kLanguageFallback.length, lessThan(30));
    });

    test('every fallback entry has a code and a label', () {
      for (final l in kLanguageFallback) {
        expect(l.code, matches(RegExp(r'^[a-z]{2}$')));
        expect(l.nativeName.trim(), isNotEmpty);
      }
    });

    test('recommended codes are all present in the fallback', () {
      // Otherwise an offline user sees a Recommended section with gaps.
      for (final code in kRecommendedCodes) {
        expect(kLanguageFallback.any((l) => l.code == code), isTrue,
            reason: '$code is recommended but missing offline');
      }
    });
  });
}
