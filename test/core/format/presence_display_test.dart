import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/format/presence_display.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/l10n/gen/app_localizations_en.dart';
import 'package:flame/l10n/gen/app_localizations_ko.dart';

// Three copies of this rule used to exist and they disagreed. These pin the
// boundaries the copies got wrong.
void main() {
  final AppLocalizations en = AppLocalizationsEn();
  final AppLocalizations ko = AppLocalizationsKo();
  final now = DateTime.utc(2026, 8, 30, 12);

  String at(Duration ago, {bool online = false, AppLocalizations? l10n}) =>
      presenceText(
        isOnline: online,
        lastSeen: now.subtract(ago),
        l10n: l10n ?? en,
        now: now,
      );

  test('online beats any last-seen value', () {
    expect(at(const Duration(days: 40), online: true), 'Online');
  });

  test('no last-seen at all reads as offline, not as "just now"', () {
    expect(
      presenceText(isOnline: false, lastSeen: null, l10n: en, now: now),
      'Offline',
    );
  });

  test('under a minute reads as "Just now", not "0m ago"', () {
    // User.lastActiveText had no sub-minute case, so someone seen forty
    // seconds ago rendered as "0m ago".
    expect(at(const Duration(seconds: 40)), 'Just now');
  });

  test('a clock skewed into the future does not render a negative age', () {
    expect(
      presenceText(
        isOnline: false,
        lastSeen: now.add(const Duration(minutes: 3)),
        l10n: en,
        now: now,
      ),
      'Just now',
    );
  });

  test('each unit takes over at its own boundary', () {
    expect(at(const Duration(minutes: 59)), '59m ago');
    expect(at(const Duration(minutes: 60)), '1h ago');
    expect(at(const Duration(hours: 23)), '23h ago');
    expect(at(const Duration(hours: 24)), '1d ago');
    expect(at(const Duration(days: 6)), '6d ago');
    expect(at(const Duration(days: 7)), 'Long ago');
  });

  test('it reads in the caller\'s language, not in English', () {
    // This is the whole point: all three copies were English literals, so the
    // chat header said "5m ago" in every locale the app ships.
    expect(at(const Duration(minutes: 5), l10n: ko), '5분 전');
    expect(at(const Duration(days: 40), online: true, l10n: ko), '온라인');
  });
}
