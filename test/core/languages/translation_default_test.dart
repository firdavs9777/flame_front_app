import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/languages/translation_default.dart';

void main() {
  group('shouldDefaultTranslationOn', () {
    test('true when the two declared sets share nothing', () {
      expect(
        shouldDefaultTranslationOn(
          viewerSpoken: const ['en'],
          partnerSpoken: const ['ko'],
        ),
        isTrue,
      );
    });

    test('false when the two sets share any language', () {
      expect(
        shouldDefaultTranslationOn(
          viewerSpoken: const ['en', 'ko'],
          partnerSpoken: const ['ko', 'ja'],
        ),
        isFalse,
      );
    });

    test('false when the viewer has declared nothing — unknown must not force it on', () {
      expect(
        shouldDefaultTranslationOn(
          viewerSpoken: const [],
          partnerSpoken: const ['ko'],
        ),
        isFalse,
      );
    });

    test('false when the partner has declared nothing', () {
      expect(
        shouldDefaultTranslationOn(
          viewerSpoken: const ['en'],
          partnerSpoken: const [],
        ),
        isFalse,
      );
    });

    test('false when neither has declared anything', () {
      expect(
        shouldDefaultTranslationOn(
          viewerSpoken: const [],
          partnerSpoken: const [],
        ),
        isFalse,
      );
    });

    test('comparison is case-insensitive', () {
      expect(
        shouldDefaultTranslationOn(
          viewerSpoken: const ['EN'],
          partnerSpoken: const ['en'],
        ),
        isFalse,
      );
    });
  });
}
