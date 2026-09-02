import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/core/navigation/app_routes.dart';
import 'package:flame/core/push/push_navigator.dart';
import 'package:flame/core/push/push_payload.dart';

void main() {
  testWidgets('pushes the payload destination onto the navigator',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    final pushed = <RouteSettings>[];

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('home')),
        onGenerateRoute: (settings) {
          pushed.add(settings);
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('pushed')),
          );
        },
      ),
    );

    final navigated = PushNavigator(key).go(
      PushPayload.fromData({
        'type': 'chat_message',
        'conversationId': 'conv-1',
      }),
    );
    await tester.pumpAndSettle();

    expect(navigated, isTrue);
    expect(pushed.single.name, AppRoutes.chat);
    expect((pushed.single.arguments as ChatRouteArgs).id, 'conv-1');
  });

  testWidgets('navigates nowhere for a payload with no destination',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    var generated = 0;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('home')),
        onGenerateRoute: (settings) {
          generated++;
          return MaterialPageRoute<void>(builder: (_) => const SizedBox());
        },
      ),
    );

    final navigated =
        PushNavigator(key).go(PushPayload.fromData({'type': 'mystery'}));
    await tester.pumpAndSettle();

    expect(navigated, isFalse);
    expect(generated, 0);
  });

  test('reports false rather than throwing when no navigator is mounted', () {
    // A tap can arrive before the first frame — getInitialMessage() is read
    // during startup. Throwing there would crash the launch it was meant to
    // route.
    final navigated = PushNavigator(GlobalKey<NavigatorState>()).go(
      PushPayload.fromData({
        'type': 'chat_message',
        'conversationId': 'conv-1',
      }),
    );

    expect(navigated, isFalse);
  });
}
