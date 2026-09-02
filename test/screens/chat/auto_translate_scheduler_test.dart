import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/screens/chat/state/auto_translate_scheduler.dart';

void main() {
  group('AutoTranslateScheduler — the delay', () {
    test('cancelling before the delay elapses means fire never runs', () {
      fakeAsync((async) {
        final gate = AutoTranslateGate();
        final scheduler = AutoTranslateScheduler();
        var fired = 0;

        scheduler.start(gate: gate, fire: () async => fired++);
        // Simulates a bubble that mounts only transiently — during the
        // opening `jumpTo` layout pass — and is disposed well inside the
        // delay window.
        scheduler.cancel();
        async.elapse(const Duration(milliseconds: 300));

        expect(fired, 0);
      });
    });

    test('cancelling exactly at the delay boundary still stops it', () {
      fakeAsync((async) {
        final gate = AutoTranslateGate();
        final scheduler = AutoTranslateScheduler(
          delay: const Duration(milliseconds: 300),
        );
        var fired = 0;

        scheduler.start(gate: gate, fire: () async => fired++);
        async.elapse(const Duration(milliseconds: 299));
        scheduler.cancel();
        async.elapse(const Duration(milliseconds: 1));

        expect(fired, 0,
            reason: 'cancelled a millisecond before the timer would fire');
      });
    });

    test('an attempt left uncancelled fires once the delay elapses',
        () {
      fakeAsync((async) {
        final gate = AutoTranslateGate();
        final scheduler = AutoTranslateScheduler();
        var fired = 0;

        scheduler.start(gate: gate, fire: () async => fired++);
        async.elapse(const Duration(milliseconds: 300));

        expect(fired, 1);
      });
    });

    test('cancelling after it already fired is a harmless no-op', () {
      fakeAsync((async) {
        final gate = AutoTranslateGate();
        final scheduler = AutoTranslateScheduler();
        var fired = 0;

        scheduler.start(gate: gate, fire: () async => fired++);
        async.elapse(const Duration(milliseconds: 300));
        expect(fired, 1);

        expect(scheduler.cancel, returnsNormally);
      });
    });
  });

  group('AutoTranslateGate — the cap', () {
    test('a 4th acquire waits until one of the first 3 releases', () {
      fakeAsync((async) {
        final gate = AutoTranslateGate(maxConcurrent: 3);
        var acquiredCount = 0;

        for (var i = 0; i < 3; i++) {
          gate.acquire().then((_) => acquiredCount++);
        }
        async.flushMicrotasks();
        expect(acquiredCount, 3, reason: 'the first 3 acquire immediately');

        var fourthAcquired = false;
        gate.acquire().then((_) => fourthAcquired = true);
        async.flushMicrotasks();
        expect(fourthAcquired, isFalse,
            reason: 'the cap is already saturated');

        gate.release();
        async.flushMicrotasks();
        expect(fourthAcquired, isTrue,
            reason: 'a released slot is handed straight to the waiter');
      });
    });

    test(
        'concurrent auto-translations never exceed the cap across a burst',
        () {
      fakeAsync((async) {
        final gate = AutoTranslateGate(maxConcurrent: 3);
        var active = 0;
        var maxObservedActive = 0;
        final release = <Completer<void>>[];

        Future<void> slowFire() async {
          active++;
          if (active > maxObservedActive) maxObservedActive = active;
          final completer = Completer<void>();
          release.add(completer);
          await completer.future;
          active--;
        }

        // A burst of 8 bubbles all wanting to auto-translate at once — more
        // than plausibly mount during one opening `jumpTo` layout pass.
        final schedulers = List.generate(
          8,
          (_) => AutoTranslateScheduler(delay: Duration.zero),
        );
        for (final s in schedulers) {
          s.start(gate: gate, fire: slowFire);
        }

        async.elapse(Duration.zero);
        async.flushMicrotasks();

        expect(active, 3);
        expect(maxObservedActive, 3,
            reason: 'the cap must never be exceeded, not even transiently');

        // Drain the burst, freeing slots one at a time.
        while (release.isNotEmpty) {
          release.removeAt(0).complete();
          async.flushMicrotasks();
          expect(active, lessThanOrEqualTo(3));
        }

        expect(maxObservedActive, 3);
      });
    });
  });
}
