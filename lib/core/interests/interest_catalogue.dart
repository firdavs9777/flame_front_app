import 'package:flutter/material.dart';

import 'package:flame/l10n/gen/app_localizations.dart';

/// One interest: a stable stored token, a localised label, and its chip styling.
///
/// The token is what `user.interests` stores and what the backend's discovery
/// `$in` matches. It is English and never translated — translating it would
/// silently break every stored value and every filter at once. Only [label]
/// varies by locale.
class Interest {
  const Interest(this.token, this.icon, this.color, this._label);

  final String token;
  final IconData icon;
  final Color color;
  final String Function(AppLocalizations) _label;

  String label(AppLocalizations l10n) => _label(l10n);
}

/// The canonical vocabulary, mirrored in the backend's `flame/config/interests.js`.
///
/// This replaces two lists that had already drifted apart: the registration step
/// offered eighteen tokens and the filter sheet sixteen, overlapping only partly.
/// `Hiking` existed in the filter alone — no user could ever hold it, so
/// filtering on it always returned nobody.
///
/// The order is the registration step's, because that is the list that produced
/// every stored value.
const List<Interest> kInterests = [
  Interest('Travel', Icons.flight_takeoff_rounded, Color(0xFF3498DB), _travel),
  Interest('Music', Icons.music_note_rounded, Color(0xFF9B59B6), _music),
  Interest('Movies', Icons.movie_creation_rounded, Color(0xFFE74C3C), _movies),
  Interest('Food', Icons.restaurant_rounded, Color(0xFFE67E22), _food),
  Interest('Fitness', Icons.fitness_center_rounded, Color(0xFF27AE60), _fitness),
  Interest('Reading', Icons.menu_book_rounded, Color(0xFF8E44AD), _reading),
  Interest('Gaming', Icons.sports_esports_rounded, Color(0xFF2980B9), _gaming),
  Interest('Art', Icons.palette_rounded, Color(0xFFD35400), _art),
  Interest('Photography', Icons.camera_alt_rounded, Color(0xFF16A085), _photography),
  Interest('Sports', Icons.sports_soccer_rounded, Color(0xFF2ECC71), _sports),
  Interest('Cooking', Icons.soup_kitchen_rounded, Color(0xFFF39C12), _cooking),
  Interest('Nature', Icons.park_rounded, Color(0xFF1ABC9C), _nature),
  Interest('Coffee', Icons.coffee_rounded, Color(0xFF795548), _coffee),
  Interest('Wine', Icons.wine_bar_rounded, Color(0xFFC0392B), _wine),
  Interest('Dancing', Icons.nightlife_rounded, Color(0xFFFF6B6B), _dancing),
  Interest('Yoga', Icons.self_improvement_rounded, Color(0xFF00BCD4), _yoga),
  Interest('Pets', Icons.pets_rounded, Color(0xFFFF9800), _pets),
  Interest('Tech', Icons.devices_rounded, Color(0xFF607D8B), _tech),
  Interest('Hiking', Icons.terrain_rounded, Color(0xFF00897B), _hiking),
];

String _travel(AppLocalizations l) => l.interestTravel;
String _music(AppLocalizations l) => l.interestMusic;
String _movies(AppLocalizations l) => l.interestMovies;
String _food(AppLocalizations l) => l.interestFood;
String _fitness(AppLocalizations l) => l.interestFitness;
String _reading(AppLocalizations l) => l.interestReading;
String _gaming(AppLocalizations l) => l.interestGaming;
String _art(AppLocalizations l) => l.interestArt;
String _photography(AppLocalizations l) => l.interestPhotography;
String _sports(AppLocalizations l) => l.interestSports;
String _cooking(AppLocalizations l) => l.interestCooking;
String _nature(AppLocalizations l) => l.interestNature;
String _coffee(AppLocalizations l) => l.interestCoffee;
String _wine(AppLocalizations l) => l.interestWine;
String _dancing(AppLocalizations l) => l.interestDancing;
String _yoga(AppLocalizations l) => l.interestYoga;
String _pets(AppLocalizations l) => l.interestPets;
String _tech(AppLocalizations l) => l.interestTech;
String _hiking(AppLocalizations l) => l.interestHiking;

/// The catalogue entry for [token], or null when it is off-catalogue.
///
/// Registration accepts free-text interests, so a stored value may not be here.
/// Callers render such a value as its raw token rather than dropping it.
Interest? interestFor(String token) {
  for (final i in kInterests) {
    if (i.token == token) return i;
  }
  return null;
}

/// The label to show for a stored interest token, in [l10n]'s language.
///
/// Both profile screens used to render the token itself, so every interest read
/// "Travel" and "Coffee" in all 32 locales — the translations existed and
/// nothing called them. Off-catalogue tokens still render as themselves, which
/// is the only honest thing to do with a value this app did not define.
String interestLabel(String token, AppLocalizations l10n) =>
    interestFor(token)?.label(l10n) ?? token;

/// The most interests a discovery filter may select, matching the backend's
/// MAX_INTEREST_FILTER.
const int kMaxInterestFilter = 10;
