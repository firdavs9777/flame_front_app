import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/languages/language_complement.dart';

void main() {
  LanguageComplement classify({
    List<String> mySpoken = const [],
    List<String> myLearning = const [],
    List<String> theirSpoken = const [],
    List<String> theirLearning = const [],
  }) =>
      languageComplement(
        viewerSpoken: mySpoken,
        viewerLearning: myLearning,
        theirSpoken: theirSpoken,
        theirLearning: theirLearning,
      );

  group('the rungs, in the order the server scores them', () {
    test('each speaking what the other is learning is the top rung', () {
      // The premise of the app: the server scores exactly this 1.0.
      expect(
        classify(
          mySpoken: ['en'],
          myLearning: ['ko'],
          theirSpoken: ['ko'],
          theirLearning: ['en'],
        ),
        LanguageComplement.mutual,
      );
    });

    test('one-directional teaching is distinguished by which direction', () {
      expect(
        classify(
          mySpoken: ['en'],
          myLearning: ['ko'],
          theirSpoken: ['ko'],
          theirLearning: ['fr'],
        ),
        LanguageComplement.theyTeachYou,
      );
      expect(
        classify(
          mySpoken: ['en'],
          myLearning: ['de'],
          theirSpoken: ['ko'],
          theirLearning: ['en'],
        ),
        LanguageComplement.youTeachThem,
      );
    });

    test('mutual beats either direction alone', () {
      // Both conditions hold here; the answer must not depend on which is
      // tested first, which is the bug an if/else-if ladder invites.
      expect(
        classify(
          mySpoken: ['en', 'ko'],
          myLearning: ['ko', 'en'],
          theirSpoken: ['ko', 'en'],
          theirLearning: ['en', 'ko'],
        ),
        LanguageComplement.mutual,
      );
    });

    test('a shared language with no teaching is its own case', () {
      expect(
        classify(
          mySpoken: ['en'],
          myLearning: ['ko'],
          theirSpoken: ['en'],
          theirLearning: ['fr'],
        ),
        LanguageComplement.shared,
      );
    });

    test('declared, with nothing in common, is none', () {
      expect(
        classify(
          mySpoken: ['en'],
          myLearning: ['ko'],
          theirSpoken: ['fr'],
          theirLearning: ['de'],
        ),
        LanguageComplement.none,
      );
    });
  });

  group('silence is not a poor match', () {
    test('either side undeclared is unknown, never none', () {
      // The server scores this NEUTRAL for the same reason: every account
      // predates the feature, and a card that said "no languages in common"
      // would be stating a fact nobody has established.
      expect(classify(theirSpoken: ['ko']), LanguageComplement.unknown);
      expect(classify(mySpoken: ['en']), LanguageComplement.unknown);
      expect(classify(), LanguageComplement.unknown);
    });

    test('learning alone is not enough — spoken is what the guard reads', () {
      expect(
        classify(myLearning: ['ko'], theirSpoken: ['ko'], theirLearning: ['en']),
        LanguageComplement.unknown,
      );
    });

    test('a list of blanks counts as undeclared', () {
      expect(
        classify(mySpoken: ['', '  '], theirSpoken: ['ko']),
        LanguageComplement.unknown,
      );
    });
  });

  group('the App Review demo data', () {
    // docs/app-store/2026-09-resubmission-metadata.md section 7 specifies the
    // demo account and two seed accounts, and the response letter tells Apple
    // that BOTH seed cards will carry the "You can teach each other" marker.
    // That is a promise made to a reviewer who has already rejected this app
    // once, so it is pinned here rather than reasoned about: change the seed
    // spec and this fails.
    const demoSpoken = ['en'];
    const demoLearning = ['ko', 'es'];

    test('the Korean seed account is a mutual match with the demo account', () {
      expect(
        classify(
          mySpoken: demoSpoken,
          myLearning: demoLearning,
          theirSpoken: ['ko'],
          theirLearning: ['en'],
        ),
        LanguageComplement.mutual,
      );
    });

    test('the Spanish seed account is too', () {
      expect(
        classify(
          mySpoken: demoSpoken,
          myLearning: demoLearning,
          theirSpoken: ['es'],
          theirLearning: ['en'],
        ),
        LanguageComplement.mutual,
      );
    });

    test('a demo account with no languages set earns no marker at all', () {
      // What the reviewer would actually see if section 7a were skipped: the
      // letter points at a badge that is not there.
      expect(
        classify(theirSpoken: ['ko'], theirLearning: ['en']),
        LanguageComplement.unknown,
      );
    });
  });

  group('codes as they actually arrive', () {
    test('case and surrounding space do not change the answer', () {
      // These have been stored since before the field was validated.
      expect(
        classify(
          mySpoken: [' EN '],
          myLearning: ['Ko'],
          theirSpoken: ['ko'],
          theirLearning: ['en'],
        ),
        LanguageComplement.mutual,
      );
    });

    test('duplicates do not change the answer', () {
      expect(
        classify(
          mySpoken: ['en', 'en'],
          myLearning: ['ko', 'ko'],
          theirSpoken: ['ko'],
          theirLearning: ['en'],
        ),
        LanguageComplement.mutual,
      );
    });
  });
}
