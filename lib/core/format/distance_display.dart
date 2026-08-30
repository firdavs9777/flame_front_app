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

/// "50 km" / "31 mi" — a distance with no direction, for a search radius.
///
/// Same unit rule as [formatDistanceAway]: the stored preference is always
/// kilometres, and only the display converts. The filter slider and the
/// read-only profile row both used a hardcoded " km", so a US reader set a
/// radius in a unit they do not think in.
///
/// Unlike [formatDistanceAway] this keeps a decimal at any magnitude. The
/// value is a preference the user set, not a measurement of someone else: a
/// stored 24.6 must not read as "25 km" here and seed an editor with 24.6 one
/// tap away. '0.#' drops the decimal only when there isn't one, so a round 50
/// still reads "50 km".
String formatDistanceValue(double km, AppLocalizations l10n, String localeName) {
  final imperial = _imperialLocales.contains(localeName);
  final value = imperial ? km / _kmPerMile : km;
  final text = NumberFormat('0.#', localeName).format(value);

  return imperial ? l10n.distanceValueMiles(text) : l10n.distanceValueKm(text);
}
