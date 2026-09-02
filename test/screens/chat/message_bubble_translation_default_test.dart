import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/translation_provider.dart';
import 'package:flame/screens/chat/widgets/message_bubble.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;
import 'package:flame/services/translation_service.dart';

/// Stands in for the network. `translationServiceProvider` normally builds a
/// real [TranslationService] backed by [ApiClient], which would hit the
/// network in a widget test — this returns a canned success instead.
class _FakeTranslationService implements TranslationService {
  @override
  Future<ServiceResult<String>> translate({
    required String text,
    required String targetLang,
    String? sourceLang,
  }) async {
    return ServiceResult.success('($targetLang) $text');
  }
}

/// Never resolves a `translate()` call until the test tells it to, and
/// records how many calls were in flight at once — the shared
/// `autoTranslateGateProvider` cap is what should keep that number bounded
/// even when every bubble in a burst wants to fire at the same moment.
class _ConcurrencyTrackingService implements TranslationService {
  int active = 0;
  int maxActive = 0;
  final List<Completer<void>> pending = [];

  @override
  Future<ServiceResult<String>> translate({
    required String text,
    required String targetLang,
    String? sourceLang,
  }) async {
    active++;
    if (active > maxActive) maxActive = active;
    final gate = Completer<void>();
    pending.add(gate);
    await gate.future;
    active--;
    return ServiceResult.success('translated: $text');
  }
}

/// Matches `AutoTranslateScheduler`'s default delay. Tests advance exactly
/// this far (rather than relying on `pumpAndSettle`, which does not drive a
/// real `Timer`'s duration) to let a not-yet-cancelled auto-trigger fire.
const kAutoTranslateTestDelay = Duration(milliseconds: 300);

Message _incomingText(String id, String text) => Message.fromJson({
      'id': id,
      'sender_id': 'partner',
      'text': text,
      'message_type': 'text',
      'created_at': '2026-08-20T09:00:00.000Z',
    });

Widget _host(Widget child) => ProviderScope(
      overrides: [
        translationServiceProvider.overrideWithValue(_FakeTranslationService()),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  group('translateDefaultOn', () {
    testWidgets('false (the default) leaves translation opt-in', (tester) async {
      final message = _incomingText('m1', 'hello');
      await tester.pumpWidget(_host(MessageBubble(message: message, isMe: false)));
      await tester.pumpAndSettle();

      // Still showing the tap-to-translate affordance, not a result.
      expect(find.text('Translate'), findsOneWidget);
      expect(find.text('(en) hello'), findsNothing);
    });

    testWidgets('true begins translation automatically, no tap required',
        (tester) async {
      final message = _incomingText('m2', 'hello');
      await tester.pumpWidget(_host(MessageBubble(
        message: message,
        isMe: false,
        translateDefaultOn: true,
      )));
      // The auto-trigger is deliberately delayed (AutoTranslateScheduler) so
      // a bubble that mounts only transiently never reaches the network —
      // pumpAndSettle alone does not advance a real Timer's duration.
      await tester.pump(kAutoTranslateTestDelay);
      await tester.pumpAndSettle();

      expect(find.text('(en) hello'), findsOneWidget);
      expect(find.text('Hide translation'), findsOneWidget);
    });

    testWidgets('true never fires for an outgoing message', (tester) async {
      final message = _incomingText('m3', 'hello');
      await tester.pumpWidget(_host(MessageBubble(
        message: message,
        isMe: true,
        translateDefaultOn: true,
      )));
      await tester.pump(kAutoTranslateTestDelay);
      await tester.pumpAndSettle();

      // isMe messages carry no translate section at all.
      expect(find.text('Translate'), findsNothing);
      expect(find.text('(en) hello'), findsNothing);
    });

    testWidgets(
        'a bubble unmounted before the delay elapses never fires a request',
        (tester) async {
      final message = _incomingText('m5', 'hello');
      final container = ProviderContainer(overrides: [
        translationServiceProvider.overrideWithValue(_FakeTranslationService()),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(
              message: message,
              isMe: false,
              translateDefaultOn: true,
            ),
          ),
        ),
      ));

      // Unmount well inside the delay window — the moral equivalent of the
      // opening `jumpTo` layout pass building and discarding a bubble before
      // the user ever actually scrolls to it.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox.shrink());

      // Let the cancelled timer's original deadline pass. If cancellation
      // did not work, the fake translation would land here.
      await tester.pump(kAutoTranslateTestDelay);
      await tester.pumpAndSettle();

      expect(container.read(translationProvider)[message.id], isNull,
          reason: 'a cancelled auto-trigger must never touch the cache, '
              'let alone the network');
    });

    testWidgets(
        'a user who hides an auto-shown translation stays hidden on rebuild',
        (tester) async {
      final message = _incomingText('m4', 'hello');
      final container = ProviderContainer(overrides: [
        translationServiceProvider.overrideWithValue(_FakeTranslationService()),
      ]);
      addTearDown(container.dispose);

      Widget host() => UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: MessageBubble(
                  message: message,
                  isMe: false,
                  translateDefaultOn: true,
                  // A fresh key each pump forces a fresh State, simulating
                  // the bubble scrolling out of and back into view.
                  key: const Key('m4-bubble'),
                ),
              ),
            ),
          );

      await tester.pumpWidget(host());
      await tester.pump(kAutoTranslateTestDelay);
      await tester.pumpAndSettle();
      expect(find.text('Hide translation'), findsOneWidget);

      await tester.tap(find.text('Hide translation'));
      await tester.pump();
      expect(find.text('Translate'), findsOneWidget);
      expect(find.text('(en) hello'), findsNothing);

      // Rebuild fresh — the cache entry is done, not idle, so initState must
      // not re-trigger and flip it visible again behind the user's back.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(host());
      await tester.pump(kAutoTranslateTestDelay);
      await tester.pumpAndSettle();

      expect(find.text('Translate'), findsOneWidget);
      expect(find.text('(en) hello'), findsNothing);
    });

    testWidgets(
        'a burst of simultaneous auto-translations never exceeds the shared cap',
        (tester) async {
      final service = _ConcurrencyTrackingService();
      final messages =
          List.generate(8, (i) => _incomingText('burst-$i', 'hello $i'));

      // A plain ListView (not .builder) inflates every child immediately, so
      // all 8 bubbles' initState fires in this one pump — the same shape as
      // the opening `jumpTo` layout pass building far more than the
      // viewport needs.
      await tester.pumpWidget(ProviderScope(
        overrides: [
          translationServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: [
                for (final m in messages)
                  MessageBubble(
                    key: ValueKey(m.id),
                    message: m,
                    isMe: false,
                    translateDefaultOn: true,
                  ),
              ],
            ),
          ),
        ),
      ));

      await tester.pump(kAutoTranslateTestDelay);
      await tester.pump();

      expect(service.active, 3,
          reason: 'the default cap (AutoTranslateGate.maxConcurrent) is 3');
      expect(service.maxActive, 3,
          reason: 'never exceeded, not even transiently');

      // Drain the burst — each freed slot should hand straight to the next
      // queued attempt rather than the cap ever climbing back above 3.
      while (service.pending.isNotEmpty) {
        service.pending.removeAt(0).complete();
        await tester.pump();
        expect(service.active, lessThanOrEqualTo(3));
      }

      expect(service.maxActive, 3);
    });
  });
}
