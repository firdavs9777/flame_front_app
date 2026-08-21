import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/discovery_provider.dart';
import 'package:flame/services/discovery_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

User _u(String id) => User.fromJson({'id': id, 'name': id, 'photos': <dynamic>[]});

class _Service extends DiscoveryService {
  _Service(this.pages);
  final List<List<String>> pages;
  int calls = 0;
  bool fail = false;
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<ServiceResult<DiscoveryResult>> getPotentialMatches({int limit = 10}) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(Duration.zero);
    inFlight--;

    if (fail) return ServiceResult.failure('offline');
    final page = calls < pages.length ? pages[calls] : <String>[];
    calls++;
    return ServiceResult.success(
        DiscoveryResult(users: page.map(_u).toList(), hasMore: page.isNotEmpty));
  }
}

void main() {
  test('load stores the first page', () async {
    final n = DiscoveryNotifier(_Service([['a', 'b']]));

    await n.load();

    expect(n.state.value!.map((u) => u.id), ['a', 'b']);
  });

  test('refill appends only profiles not already held', () async {
    // The head necessarily re-includes anything fetched but not yet swiped.
    final n = DiscoveryNotifier(_Service([['a', 'b'], ['b', 'c']]));
    await n.load();

    await n.refill();

    expect(n.state.value!.map((u) => u.id), ['a', 'b', 'c']);
  });

  test('concurrent refills make one request', () async {
    final service = _Service([['a'], ['b']]);
    final n = DiscoveryNotifier(service);
    await n.load();

    await Future.wait([n.refill(), n.refill(), n.refill()]);

    expect(service.maxInFlight, 1,
        reason: 'the notifier had no in-flight guard, so a double fire advanced '
            'the offset twice and appended without deduping');
  });

  test('a failed refill keeps the deck', () async {
    final service = _Service([['a', 'b']]);
    final n = DiscoveryNotifier(service);
    await n.load();

    service.fail = true;
    await n.refill();

    expect(n.state.value!.map((u) => u.id), ['a', 'b']);
  });

  test('a failed initial load is an error, not an empty deck', () async {
    final n = DiscoveryNotifier(_Service([])..fail = true);

    await n.load();

    expect(n.state.hasError, isTrue);
    expect(n.state.valueOrNull, isNull,
        reason: 'an error must never render as "you have seen everyone"');
  });

  test('an empty first page is an empty deck, not an error', () async {
    final n = DiscoveryNotifier(_Service([[]]));

    await n.load();

    expect(n.state.hasError, isFalse);
    expect(n.state.value, isEmpty);
    expect(n.hasMore, isFalse);
  });

  test('refill stops once the server says there is no more', () async {
    final service = _Service([[]]);
    final n = DiscoveryNotifier(service);
    await n.load();

    await n.refill();

    expect(service.calls, 1, reason: 'hasMore was false');
  });

  test('removeUser drops one card and undoRemove puts it back in front', () async {
    final n = DiscoveryNotifier(_Service([['a', 'b']]));
    await n.load();
    final first = n.state.value!.first;

    n.removeUser('a');
    expect(n.state.value!.map((u) => u.id), ['b']);

    n.undoRemove(first);
    expect(n.state.value!.map((u) => u.id), ['a', 'b']);
  });

  test('clearAndReload empties before refetching', () async {
    // Applying changed filters cannot merge: the cards already held were chosen
    // under the old predicate, so keeping them shows results the new filters
    // exclude, which reads as the filter not working.
    final n = DiscoveryNotifier(_Service([['a', 'b'], ['c']]));
    await n.load();

    await n.clearAndReload();

    expect(n.state.value!.map((u) => u.id), ['c']);
  });
}
