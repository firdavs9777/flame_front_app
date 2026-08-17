import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/chat/chat_search_screen.dart';

Message _msg(String id, String text) => Message.fromJson({
  'id': id,
  'sender_id': 'u1',
  'text': text,
  'type': 'text',
  'created_at': '2026-08-17T00:00:00.000Z',
});

void main() {
  Widget host(MessageSearch search) =>
      MaterialApp(home: ChatSearchScreen(search: search));

  testWidgets('does not search until typing settles', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host((q, {int limit = 20, int offset = 0}) async {
      calls++;
      return [_msg('m1', q)];
    }));

    await tester.enterText(find.byType(TextField), 'h');
    await tester.enterText(find.byType(TextField), 'he');
    await tester.enterText(find.byType(TextField), 'hel');
    await tester.pump(const Duration(milliseconds: 100));

    // The route allows twenty searches a minute. A call per keystroke spends
    // three of them on one word.
    expect(calls, 0);

    await tester.pump(const Duration(milliseconds: 600));
    expect(calls, 1);
  });

  testWidgets('shows results', (tester) async {
    await tester.pumpWidget(host(
      (q, {int limit = 20, int offset = 0}) async => [_msg('m1', 'found you')],
    ));

    await tester.enterText(find.byType(TextField), 'found');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('found you'), findsOneWidget);
  });

  testWidgets('clearing the query clears the results without searching', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(host((q, {int limit = 20, int offset = 0}) async {
      calls++;
      return [_msg('m1', 'found you')];
    }));

    await tester.enterText(find.byType(TextField), 'found');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('found you'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.text('found you'), findsNothing);
    expect(calls, 1, reason: 'an empty query is not a search');
  });

  testWidgets('whitespace alone is not a search', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host((q, {int limit = 20, int offset = 0}) async {
      calls++;
      return [];
    }));

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump(const Duration(milliseconds: 600));

    expect(calls, 0, reason: 'the backend 422s an empty q; do not spend the call');
  });

  testWidgets('an empty result set says so rather than showing nothing', (
    tester,
  ) async {
    await tester.pumpWidget(host(
      (q, {int limit = 20, int offset = 0}) async => [],
    ));

    await tester.enterText(find.byType(TextField), 'nothing');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.textContaining('No messages'), findsOneWidget);
  });

  testWidgets('a failure is shown, not swallowed', (tester) async {
    await tester.pumpWidget(host(
      (q, {int limit = 20, int offset = 0}) async => throw Exception('offline'),
    ));

    await tester.enterText(find.byType(TextField), 'boom');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.textContaining('Search failed'), findsOneWidget);
  });

  testWidgets('a slow response that lands after disposal does not throw', (
    tester,
  ) async {
    await tester.pumpWidget(host((q, {int limit = 20, int offset = 0}) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return [_msg('m1', 'late')];
    }));

    await tester.enterText(find.byType(TextField), 'late');
    await tester.pump(const Duration(milliseconds: 600));

    // Leave the screen while the request is still in flight.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
  });
}
