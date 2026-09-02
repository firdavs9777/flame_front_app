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
      await tester.pumpAndSettle();

      // isMe messages carry no translate section at all.
      expect(find.text('Translate'), findsNothing);
      expect(find.text('(en) hello'), findsNothing);
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
      await tester.pumpAndSettle();

      expect(find.text('Translate'), findsOneWidget);
      expect(find.text('(en) hello'), findsNothing);
    });
  });
}
