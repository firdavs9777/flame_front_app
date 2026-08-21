import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/format/distance_display.dart';
import 'package:flame/l10n/gen/app_localizations.dart';

void main() {
  late AppLocalizations en;
  late AppLocalizations ko;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    ko = await AppLocalizations.delegate.load(const Locale('ko'));
  });

  test('US English reads in miles', () {
    // 16 km is about 10 miles. "16 km away" is wrong for a US reader in a way a
    // translation alone would not fix.
    final text = formatDistanceAway(16, en, 'en_US');
    expect(text, contains('10'));
    expect(text.toLowerCase(), contains('mi'));
  });

  test('metric locales read in kilometres', () {
    expect(formatDistanceAway(16, ko, 'ko'), contains('16'));
    expect(formatDistanceAway(16, en, 'en_GB'), contains('16'));
    expect(formatDistanceAway(16, en, 'en_GB').toLowerCase(), contains('km'));
  });

  test('under a kilometre is not rounded to zero', () {
    final text = formatDistanceAway(0.4, ko, 'ko');
    expect(text, contains('0.4'),
        reason: 'rounding to "0 km away" is the bug being removed');
  });

  test('a large distance carries no decimals', () {
    final text = formatDistanceAway(344.29, ko, 'ko');
    expect(text, contains('344'));
    expect(text, isNot(contains('344.')));
  });
}
