// The deck used to skip every other profile.
//
// CardSwiper keeps its own cursor and only ever advances it — didUpdateWidget
// does not reset it when cardsCount changes. SwipeNotifier removed the swiped
// user from the deck on every swipe, so the list shrank by one while the cursor
// grew by one: after swiping u0 the cursor pointed at index 1 of a list that no
// longer contained u0, which is u2. u1 was never rendered, never swiped, and
// never sent to the server. The skipped cards piled up at the head until the
// cursor ran past the end and cardBuilder returned blank cards that no longer
// reached the server at all.
//
// This walks a real deck through the real providers and asserts that every
// profile is both shown and swiped, exactly once.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/discovery_provider.dart';
import 'package:flame/providers/location_provider.dart';
import 'package:flame/providers/swipe_provider.dart';
import 'package:flame/screens/discover/discover_screen.dart';
import 'package:flame/services/discovery_service.dart';
import 'package:flame/services/location_service.dart';
import 'package:flame/services/swipe_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

User _u(String id) => User.fromJson({
      'id': id, 'name': id, 'age': 25, 'bio': '', 'interests': <String>[],
      'gender': 'female', 'looking_for': 'male', 'photos': <String>[],
    });

final _deck = [for (var i = 0; i < 6; i++) _u('u$i')];

class _Deck extends DiscoveryService {
  @override
  Future<ServiceResult<DiscoveryResult>> getPotentialMatches({int limit = 10}) async =>
      ServiceResult.success(DiscoveryResult(users: _deck, hasMore: false));
}

/// Records who the app actually told the server about.
class _RecordingSwipes extends SwipeService {
  final passed = <String>[];

  @override
  Future<ServiceResult<SwipeResult>> passUser(String userId) async {
    passed.add(userId);
    return ServiceResult.success(SwipeResult(isMatch: false));
  }
}

late _RecordingSwipes swipes;

Widget _host() {
  swipes = _RecordingSwipes();
  return ProviderScope(
    overrides: [
      discoveryProvider.overrideWith((ref) => DiscoveryNotifier(_Deck())),
      swipeProvider.overrideWith((ref) => SwipeNotifier(swipes, ref)),
      // Location is enrichment; the deck must never wait on it.
      locationRefresherProvider.overrideWithValue(LocationRefresher(
        getPosition: () async => LocationResult.failure('no location in tests'),
        push: (_, __, {city, state, country}) async => false,
      )),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: const DiscoverScreen(),
    ),
  );
}

void main() {
  testWidgets('every card in the deck is shown and swiped, none skipped',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final seen = <String>[];
    for (var i = 0; i < _deck.length; i++) {
      // Whatever is on top right now.
      final onTop = _deck.map((u) => u.id).where(
            (id) => find.text(id).evaluate().isNotEmpty,
          );
      seen.addAll(onTop.take(1));

      await tester.drag(find.byType(DiscoverScreen), const Offset(-600, 0));
      await tester.pumpAndSettle();
    }

    expect(
      swipes.passed,
      _deck.map((u) => u.id).toList(),
      reason: 'every profile must reach the server, in deck order — the '
          'shrinking-list bug sent only u0, u2, u4 and then nothing',
    );
    expect(swipes.passed.toSet().length, swipes.passed.length,
        reason: 'and none of them twice');
  });
}
