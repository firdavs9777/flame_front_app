import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/validation/auth_validators.dart';
import 'package:flame/l10n/gen/app_localizations.dart';

void main() {
  late AuthValidators v;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    v = AuthValidators(await AppLocalizations.delegate.load(const Locale('en')));
  });

  group('email', () {
    test('accepts a plain address', () {
      expect(v.email('ada@example.com'), isNull);
    });

    test('accepts plus addressing — the old regex rejected this', () {
      expect(v.email('ada+dating@gmail.com'), isNull);
    });

    test('accepts a TLD longer than four characters', () {
      expect(v.email('ada@science.museum'), isNull);
    });

    test('accepts a subdomain', () {
      expect(v.email('ada@mail.example.co.uk'), isNull);
    });

    test('rejects empty', () {
      expect(v.email(''), isNotNull);
      expect(v.email(null), isNotNull);
    });

    test('rejects an address with no @', () {
      expect(v.email('adaexample.com'), isNotNull);
    });

    test('rejects an address with no domain dot', () {
      expect(v.email('ada@example'), isNotNull);
    });

    test('rejects whitespace inside', () {
      expect(v.email('ada @example.com'), isNotNull);
    });
  });

  group('password', () {
    test('accepts exactly the 8-character minimum', () {
      expect(v.password('abcdefgh'), isNull);
    });

    test('rejects 7 characters', () {
      expect(v.password('abcdefg'), isNotNull);
    });

    test('accepts exactly the 128-character ceiling', () {
      expect(v.password('a' * 128), isNull);
    });

    test('rejects 129 characters — the server 422s on these today', () {
      expect(v.password('a' * 129), isNotNull);
    });

    test('does NOT require an uppercase letter or a digit', () {
      expect(v.password('allcharsnodigits'), isNull);
    });

    test('rejects empty', () {
      expect(v.password(''), isNotNull);
      expect(v.password(null), isNotNull);
    });
  });

  group('confirmPassword', () {
    test('accepts a match', () {
      expect(v.confirmPassword('hunter22', against: 'hunter22'), isNull);
    });

    test('rejects a mismatch', () {
      expect(v.confirmPassword('hunter22', against: 'hunter23'), isNotNull);
    });

    test('rejects empty', () {
      expect(v.confirmPassword('', against: 'hunter22'), isNotNull);
    });
  });

  group('name', () {
    test('accepts a two-character name', () {
      expect(v.name('Jo'), isNull);
    });

    test('rejects one character', () {
      expect(v.name('J'), isNotNull);
    });

    test('accepts exactly 50 characters', () {
      expect(v.name('a' * 50), isNull);
    });

    test('rejects 51 characters', () {
      expect(v.name('a' * 51), isNotNull);
    });

    test('rejects empty', () {
      expect(v.name(''), isNotNull);
    });
  });

  group('requiredField', () {
    test('accepts any non-empty value, however short', () {
      expect(v.requiredField('abc'), isNull);
    });

    test('rejects empty — but imposes no length rule', () {
      expect(v.requiredField(''), isNotNull);
    });
  });
}
