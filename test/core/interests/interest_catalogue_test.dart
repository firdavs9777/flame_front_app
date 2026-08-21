import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/interests/interest_catalogue.dart';
import 'package:flame/l10n/gen/app_localizations.dart';

void main() {
  test('tokens are unique and non-empty', () {
    final tokens = kInterests.map((i) => i.token).toList();
    expect(tokens.toSet().length, tokens.length);
    expect(tokens.any((t) => t.trim().isEmpty), isFalse);
  });

  test('every token has a label in English and Korean', () async {
    final en = await AppLocalizations.delegate.load(const Locale('en'));
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));

    for (final interest in kInterests) {
      expect(interest.label(en).trim(), isNotEmpty,
          reason: '${interest.token} has no English label');
      expect(interest.label(ko).trim(), isNotEmpty,
          reason: '${interest.token} has no Korean label');
    }
  });

  test('labels are translated, not echoed tokens', () async {
    final ko = await AppLocalizations.delegate.load(const Locale('ko'));

    expect(interestFor('Travel')!.label(ko), isNot('Travel'),
        reason: 'a Korean user must not read the stored English token');
  });

  test('interestFor returns null for an off-catalogue token', () {
    // Registration accepts free-text interests, so stored values may not be in
    // the catalogue. Callers must be able to detect that rather than crash.
    expect(interestFor('NotAnInterest'), isNull);
  });

  test('the catalogue matches the backend token list', () {
    // Two hardcoded lists in two repos is the situation; this is the tripwire.
    // Update flame/config/interests.js in the backend repo alongside any change.
    const backendTokens = [
      'Travel', 'Music', 'Movies', 'Food', 'Fitness', 'Reading', 'Gaming', 'Art',
      'Photography', 'Sports', 'Cooking', 'Nature', 'Coffee', 'Wine', 'Dancing',
      'Yoga', 'Pets', 'Tech', 'Hiking',
    ];
    expect(kInterests.map((i) => i.token).toList(), backendTokens);
    expect(kMaxInterestFilter, 10);
  });

  test('the catalogue is the union of what the two old lists offered', () {
    final tokens = kInterests.map((i) => i.token).toSet();

    // Registration-only tokens: users already hold these.
    for (final t in ['Wine', 'Pets', 'Tech']) {
      expect(tokens, contains(t), reason: '$t is stored on real accounts');
    }
    // Filter-only token: nobody could hold it, so filtering on it matched nobody.
    expect(tokens, contains('Hiking'));
  });
}
