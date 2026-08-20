/// Age arithmetic for the profile's date-of-birth picker.
///
/// The server stores an integer `age` (18-100) and has no birthdate field, so
/// the picker computes an age from the date chosen and sends that. Reopening the
/// screen therefore shows a date derived from the stored age rather than the
/// user's real birthday — a deliberate trade, recorded here so the next reader
/// does not mistake it for a bug. Storing the real date needs a backend field.
///
/// These are free functions taking an explicit `now` so the whole 18+ rule is
/// testable without pumping a dialog or waiting for a birthday.
library;

/// Completed years between [birthDate] and [now].
///
/// Subtracting years alone is wrong for most of the calendar: someone born on
/// 31 December 2008 is 17, not 18, for all but one day of 2026.
int ageOn(DateTime birthDate, {required DateTime now}) {
  var age = now.year - birthDate.year;
  final hadBirthdayThisYear = now.month > birthDate.month ||
      (now.month == birthDate.month && now.day >= birthDate.day);
  if (!hadBirthdayThisYear) age -= 1;
  return age;
}

/// A birthdate that yields exactly [age] today — what the picker opens on.
DateTime birthDateForAge(int age, {required DateTime now}) {
  return DateTime(now.year - age, now.month, now.day);
}

/// The latest birthdate still old enough, i.e. the picker's `lastDate`.
///
/// Bounding the picker is why the minimum age needs no error message: an
/// under-age date cannot be selected in the first place, which beats validating
/// it after the user has stopped thinking about it.
DateTime latestBirthDateFor(int minimumAge, {required DateTime now}) {
  return birthDateForAge(minimumAge, now: now);
}

/// The earliest birthdate still young enough, i.e. the picker's `firstDate`.
DateTime earliestBirthDateFor(int maximumAge, {required DateTime now}) {
  return birthDateForAge(maximumAge, now: now);
}
