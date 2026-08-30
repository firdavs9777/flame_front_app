// Undo shipped as a client-side feature wired to a controller that answered
// {undone: false} unconditionally — it had never worked once. It also had no
// button, so nothing in the app ever called it.
//
// Now the server takes the swipe back, and the deck is append-only, so the
// card is still in the list: the swiper's cursor steps back onto it. Putting
// the user back into the list — what the old undo did — would duplicate them.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/discovery_provider.dart';
import 'package:flame/providers/swipe_provider.dart';
import 'package:flame/providers/user_provider.dart';
import 'package:flame/services/discovery_service.dart';
import 'package:flame/services/swipe_service.dart';
import 'package:flame/services/user_service.dart';

User _u(String id, {bool premium = true}) => User.fromJson({
      'id': id, 'name': id, 'age': 25, 'bio': '', 'interests': const <String>[],
      'gender': 'female', 'looking_for': 'male', 'photos': const <String>[],
      'is_premium': premium,
    });

class _Swipes extends SwipeService {
  _Swipes({this.undone = true, this.reason});
  final bool undone;
  final String? reason;
  int undoCalls = 0;

  @override
  Future<ServiceResult<SwipeResult>> passUser(String id) async =>
      ServiceResult.success(SwipeResult(isMatch: false));

  @override
  Future<ServiceResult<SwipeResult>> undoLastSwipe() async {
    undoCalls++;
    return ServiceResult.success(
      SwipeResult(undone: undone, undoReason: reason),
    );
  }
}

class _NoDeck extends DiscoveryService {
  @override
  Future<ServiceResult<DiscoveryResult>> getPotentialMatches({int limit = 10}) async =>
      ServiceResult.success(const DiscoveryResult(users: [], hasMore: false));
}

ProviderContainer _container(_Swipes swipes, {bool premium = true}) {
  final c = ProviderContainer(overrides: [
    currentUserProvider.overrideWith(
      (ref) => CurrentUserNotifier(UserService())..setUser(_u('me', premium: premium)),
    ),
    discoveryProvider.overrideWith((ref) => DiscoveryNotifier(_NoDeck())),
    swipeProvider.overrideWith((ref) => SwipeNotifier(swipes, ref)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('with nothing swiped there is nothing to undo, and no request', () async {
    final swipes = _Swipes();
    final c = _container(swipes);

    final out = await c.read(swipeProvider.notifier).undo();

    expect(out, UndoOutcome.nothingToUndo);
    expect(swipes.undoCalls, 0, reason: 'no swipe, no round trip');
  });

  test('a non-premium account is told why, not shown a blank error', () async {
    final swipes = _Swipes();
    final c = _container(swipes, premium: false);
    await c.read(swipeProvider.notifier).pass(_u('them'));

    final out = await c.read(swipeProvider.notifier).undo();

    expect(out, UndoOutcome.premiumOnly);
    expect(swipes.undoCalls, 0);
  });

  test('a successful undo leaves the deck alone', () async {
    // The deck is append-only, so the card never left it.
    final swipes = _Swipes();
    final c = _container(swipes);
    await c.read(swipeProvider.notifier).pass(_u('them'));

    final out = await c.read(swipeProvider.notifier).undo();

    expect(out, UndoOutcome.undone);
    expect(swipes.undoCalls, 1);
    expect(
      c.read(discoveryProvider).valueOrNull ?? const <User>[],
      isEmpty,
      reason: 'the old undo pushed the user onto the front of the deck; with '
          'an append-only deck that duplicates a card already in it',
    );
  });

  test('a successful undo clears the state that allows another', () async {
    final c = _container(_Swipes());
    await c.read(swipeProvider.notifier).pass(_u('them'));
    expect(c.read(swipeProvider).canUndo, isTrue);

    await c.read(swipeProvider.notifier).undo();

    expect(c.read(swipeProvider).canUndo, isFalse);
  });

  test('a refusal because the match was messaged is named, not generic', () async {
    // "You've already messaged this match" and "something went wrong" send the
    // user to two completely different places.
    final swipes = _Swipes(undone: false, reason: 'ALREADY_MESSAGED');
    final c = _container(swipes);
    await c.read(swipeProvider.notifier).pass(_u('them'));

    final out = await c.read(swipeProvider.notifier).undo();

    expect(out, UndoOutcome.alreadyMessaged);
  });

  test('an unrecognised refusal falls back rather than throwing', () async {
    final swipes = _Swipes(undone: false, reason: 'SOMETHING_NEW');
    final c = _container(swipes);
    await c.read(swipeProvider.notifier).pass(_u('them'));

    expect(await c.read(swipeProvider.notifier).undo(), UndoOutcome.failed);
  });
}
