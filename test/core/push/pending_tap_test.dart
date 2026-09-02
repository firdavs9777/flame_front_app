import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/navigation/app_routes.dart';
import 'package:flame/core/push/push_navigator.dart';
import 'package:flame/core/push/push_payload.dart';

/// The cold-start case, which is the common one.
///
/// `attachHandlers()` reads `getInitialMessage()` before `runApp()`, because
/// FCM delivers the launch notification exactly once. At that moment the
/// navigator key has no state, so the tap can only be remembered. Dropping it
/// there is what made a notification that launched the app open nothing.
///
/// PushService itself cannot be constructed in a unit test — it reaches
/// FirebaseMessaging.instance — so these exercise the queue's logic through
/// the same PushNavigator it uses, with a payload standing in for the message.
void main() {
  late GlobalKey<NavigatorState> key;
  late List<RouteSettings> pushed;

  Widget host() => MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('home')),
        onGenerateRoute: (settings) {
          pushed.add(settings);
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('pushed')),
          );
        },
      );

  setUp(() {
    key = GlobalKey<NavigatorState>();
    pushed = <RouteSettings>[];
  });

  testWidgets('a tap with no navigator is not delivered, so it must be held',
      (tester) async {
    final payload = PushPayload.fromData({
      'type': 'chat_message',
      'conversationId': 'conv-1',
    });

    // Before any widget tree — exactly the state main() is in when
    // getInitialMessage() resolves.
    final deliveredAtStartup = PushNavigator(key).go(payload);
    expect(deliveredAtStartup, isFalse,
        reason: 'nothing to navigate with yet — this is why it is queued');

    // ...and once the app is up, the same payload does arrive.
    await tester.pumpWidget(host());
    final deliveredAfterMount = PushNavigator(key).go(payload);
    await tester.pumpAndSettle();

    expect(deliveredAfterMount, isTrue);
    expect(pushed.single.name, AppRoutes.chat);
    expect((pushed.single.arguments as ChatRouteArgs).id, 'conv-1');
  });

  testWidgets('replaying a held tap lands on the conversation it named',
      (tester) async {
    await tester.pumpWidget(host());

    // A queue of one, which is all PushService keeps: a second launch
    // notification replaces the first rather than stacking screens.
    PushPayload? pending = PushPayload.fromData({
      'type': 'chat_message',
      'conversationId': 'conv-held',
    });
    pending = PushPayload.fromData({
      'type': 'chat_message',
      'conversationId': 'conv-newer',
    });

    PushNavigator(key).go(pending);
    await tester.pumpAndSettle();

    expect(pushed, hasLength(1));
    expect((pushed.single.arguments as ChatRouteArgs).id, 'conv-newer');
  });

  testWidgets('a payload with no destination never navigates when replayed',
      (tester) async {
    await tester.pumpWidget(host());

    // A re-engagement push opens the app and nothing more. Flushing it must
    // not push an empty route onto the stack.
    final delivered = PushNavigator(key).go(
      PushPayload.fromData({'type': 'reengagement'}),
    );
    await tester.pumpAndSettle();

    expect(delivered, isFalse);
    expect(pushed, isEmpty);
  });
}
