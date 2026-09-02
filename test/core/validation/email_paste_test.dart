import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/validation/auth_validators.dart';
import 'package:flame/l10n/gen/app_localizations.dart';

/// App Review, 2026-09-02, Guideline 2.1:
///
///   "We were unable to sign in with the following demo account credentials"
///
/// The screenshot showed `appreview1@banatalk.com` in the field, with
/// "Please enter a valid email" underneath it. The address was correct — the
/// problem was invisible. kEmailPattern is anchored, so a single trailing
/// space from a copy-paste fails it, and the field renders identically either
/// way.
///
/// Every submit path already trimmed. The validator did not, so the form never
/// validated and Sign in never ran.
void main() {
  late AuthValidators v;

  setUpAll(() async {
    v = AuthValidators(await AppLocalizations.delegate.load(const Locale('en')));
  });

  const address = 'appreview1@banatalk.com';

  test('the demo account address is accepted exactly as it is', () {
    expect(v.email(address), isNull);
  });

  group('invisible characters a paste carries in', () {
    final pastes = {
      'trailing space': '$address ',
      'leading space': ' $address',
      'both': '  $address  ',
      'trailing newline': '$address\n',
      'tab': '\t$address',
      // Not whitespace by Unicode, so trim() alone would not save this one.
      'zero-width space': '$address​',
      'zero-width non-joiner': '$address‌',
      'byte-order mark': '﻿$address',
      'non-breaking space': '$address ',
    };

    pastes.forEach((label, value) {
      test('accepts an address with a $label', () {
        expect(v.email(value), isNull,
            reason: 'this is what App Review saw rejected');
      });
    });
  });

  test('genuinely invalid addresses are still rejected', () {
    // The fix must not turn the validator into a rubber stamp.
    for (final bad in [
      'not-an-email',
      'missing@tld',
      '@nolocalpart.com',
      'spaces in@middle.com',
      'trailing@dot.',
    ]) {
      expect(v.email(bad), isNotNull, reason: '"$bad" must not pass');
    }
  });

  test('an empty or whitespace-only field still reports "required"', () {
    // Distinct from "invalid": the user has typed nothing, and saying their
    // address is malformed would be wrong.
    expect(v.email(''), isNotNull);
    expect(v.email('   '), isNotNull);
    expect(v.email(null), isNotNull);
    expect(v.email('   '), equals(v.email('')),
        reason: 'whitespace-only is empty, not invalid');
  });

  group('normalizeEmail', () {
    test('strips what is invisible and nothing else', () {
      expect(normalizeEmail('  $address​\n'), address);
      expect(normalizeEmail(address), address);
      expect(normalizeEmail(null), '');
    });

    test('does not lowercase or otherwise rewrite the address', () {
      // Case-folding is the server's business — the local part is technically
      // case-sensitive, and silently rewriting what someone typed is a
      // different decision from removing characters they did not type.
      expect(normalizeEmail(' Appreview1@banatalk.com '),
          'Appreview1@banatalk.com');
    });
  });
}
