import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/match_provider.dart';
import 'package:flame/services/match_service.dart';

// A MatchesNotifier that skips real loading and starts from a fixed list, so
// removeMatch can be exercised without hitting the network. The constructor
// only stores the MatchService — it does not call it — so this opens no
// connection.
class _SeededMatches extends MatchesNotifier {
  _SeededMatches(List<Match> initial) : super(MatchService()) {
    state = AsyncValue.data(initial);
  }
}

// Matches are built through Match.fromJson rather than the constructor so the
// test does not have to know User's required fields — and it doubles as a check
// that the backend's payload keys are the ones the app actually parses.
Match _match(String id) => Match.fromJson({
      'id': id,
      'user': {'id': 'u-$id', 'name': 'User $id'},
      'matched_at': '2026-08-16T00:00:00.000Z',
      'is_new': true,
    });

void main() {
  test('Match.fromJson reads the keys the backend sends', () {
    final m = _match('m1');
    expect(m.id, 'm1');
    expect(m.user.id, 'u-m1');
    expect(m.isNew, isTrue);
  });

  test('removeMatch drops only the targeted match', () {
    final notifier = _SeededMatches([_match('m1'), _match('m2')]);

    notifier.removeMatch('m1');

    final remaining = notifier.state.valueOrNull!;
    expect(remaining.length, 1);
    expect(remaining.single.id, 'm2');
  });

  test('removeMatch on an unknown id leaves state untouched', () {
    final notifier = _SeededMatches([_match('m1'), _match('m2')]);

    notifier.removeMatch('nope');

    expect(notifier.state.valueOrNull!.length, 2);
  });
}
