import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/date/age.dart';

// The 18+ rule moved out of a validator and into the picker's bounds, so this
// arithmetic is now what enforces it. Every case here is a date where naive
// year subtraction gives the wrong answer.
void main() {
  group('ageOn', () {
    test('the day before a birthday, the age has not ticked over', () {
      expect(
        ageOn(DateTime(2008, 8, 21), now: DateTime(2026, 8, 20)),
        17,
        reason: 'year subtraction alone would say 18 and let a minor through',
      );
    });

    test('on the birthday itself, it has', () {
      expect(ageOn(DateTime(2008, 8, 20), now: DateTime(2026, 8, 20)), 18);
    });

    test('the day after, unchanged', () {
      expect(ageOn(DateTime(2008, 8, 19), now: DateTime(2026, 8, 20)), 18);
    });

    test('a December birthday early in the year', () {
      expect(ageOn(DateTime(2008, 12, 31), now: DateTime(2026, 1, 1)), 17);
    });

    test('a January birthday late in the year', () {
      expect(ageOn(DateTime(2008, 1, 1), now: DateTime(2026, 12, 31)), 18);
    });

    test('a 29 February birthday in a non-leap year', () {
      // Born on a leap day; by 1 March of a non-leap year the birthday has
      // passed on any sane reading.
      expect(ageOn(DateTime(2008, 2, 29), now: DateTime(2026, 3, 1)), 18);
      expect(ageOn(DateTime(2008, 2, 29), now: DateTime(2026, 2, 28)), 17);
    });
  });

  group('picker bounds', () {
    final now = DateTime(2026, 8, 20);

    test('the latest allowed birthdate is exactly the minimum age', () {
      final latest = latestBirthDateFor(18, now: now);
      expect(ageOn(latest, now: now), 18);
    });

    test('one day later than that would be under age', () {
      final latest = latestBirthDateFor(18, now: now);
      final tooYoung = latest.add(const Duration(days: 1));
      expect(ageOn(tooYoung, now: now), 17);
    });

    test('the earliest allowed birthdate is exactly the maximum age', () {
      final earliest = earliestBirthDateFor(100, now: now);
      expect(ageOn(earliest, now: now), 100);
    });

    test('birthDateForAge round-trips through ageOn for every allowed age', () {
      for (var age = 18; age <= 100; age++) {
        expect(
          ageOn(birthDateForAge(age, now: now), now: now),
          age,
          reason: 'the picker opens on this date, so it must read back as $age',
        );
      }
    });
  });
}
