import 'package:intl/intl.dart';

import 'package:flame/l10n/gen/app_localizations.dart';

/// Locales that read distance in miles rather than kilometres.
///
/// The wire is always kilometres; this is display only. A US reader seeing
/// "16 km away" is a bug that no amount of translating the word "away" fixes.
const _imperialLocales = {'en_US', 'en-US', 'en_LR', 'en-LR', 'my'};

const double _kmPerMile = 1.609344;

/// "10 mi away" / "16 km away", in [l10n]'s language and [localeName]'s units.
String formatDistanceAway(double km, AppLocalizations l10n, String localeName) {
  final imperial = _imperialLocales.contains(localeName);
  final value = imperial ? km / _kmPerMile : km;

  // One decimal below the unit, none above: "0.4 km away" is useful and
  // "344.3 km away" is noise — and rounding the first to "0 km away" would
  // reintroduce exactly the fabricated label this replaces.
  final pattern = value < 1 ? '0.#' : '0';
  final text = NumberFormat(pattern, localeName).format(value);

  return imperial ? l10n.distanceAwayMiles(text) : l10n.distanceAwayKm(text);
}
