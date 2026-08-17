import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/chat/archived_conversations_screen.dart';

Conversation _conv(String id, String otherId) => Conversation.fromJson({
  'id': id,
  'other_user': {'id': otherId, 'name': 'User $otherId'},
  'unread_count': 0,
  'last_message_at': '2026-08-17T00:00:00.000Z',
});

void main() {
  Widget host({
    required ArchivedLoader load,
    ArchivedAction? unarchive,
  }) => MaterialApp(
    home: ArchivedConversationsScreen(
      load: load,
      unarchive: unarchive ?? (_) async => null,
    ),
  );

  testWidgets('lists what it loaded', (tester) async {
    await tester.pumpWidget(host(
      load: () async => [_conv('c1', 'u1'), _conv('c2', 'u2')],
    ));
    await tester.pump();

    expect(find.text('User u1'), findsOneWidget);
    expect(find.text('User u2'), findsOneWidget);
  });

  testWidgets('says so when there are none', (tester) async {
    await tester.pumpWidget(host(load: () async => []));
    await tester.pump();

    expect(find.textContaining('No archived'), findsOneWidget);
  });

  testWidgets('a load failure is shown, not a blank screen', (tester) async {
    await tester.pumpWidget(host(
      load: () async => throw Exception('offline'),
    ));
    await tester.pump();

    expect(find.textContaining('Could not load'), findsOneWidget);
  });

  testWidgets('unarchiving removes the row', (tester) async {
    final unarchived = <String>[];
    await tester.pumpWidget(host(
      load: () async => [_conv('c1', 'u1'), _conv('c2', 'u2')],
      unarchive: (id) async {
        unarchived.add(id);
        return null;
      },
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.unarchive_outlined).first);
    await tester.pump();

    expect(unarchived, ['c1']);
    expect(find.text('User u1'), findsNothing);
    expect(find.text('User u2'), findsOneWidget);
  });

  testWidgets('a failed unarchive keeps the row and shows the error', (
    tester,
  ) async {
    await tester.pumpWidget(host(
      load: () async => [_conv('c1', 'u1')],
      unarchive: (_) async => 'Could not unarchive',
    ));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.unarchive_outlined));
    await tester.pump();

    // Removing a row whose server-side state did not change would show the
    // user something untrue.
    expect(find.text('User u1'), findsOneWidget);
    expect(find.text('Could not unarchive'), findsOneWidget);
  });
}
