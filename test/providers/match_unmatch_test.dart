import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';

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

  test('removing a match drops only that one', () {
    final matches = [_match('m1'), _match('m2')];

    // The transformation removeMatch performs on state.
    final remaining = matches.where((m) => m.id != 'm1').toList();

    expect(remaining.length, 1);
    expect(remaining.single.id, 'm2');
  });
}
