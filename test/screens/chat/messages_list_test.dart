import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/screens/chat/chat_rows.dart';
import 'package:flame/screens/chat/error/chat_error_widget.dart';
import 'package:flame/screens/chat/message/conversation_empty_state.dart';
import 'package:flame/screens/chat/message/date_separator_chip.dart';
import 'package:flame/screens/chat/message/messages_list.dart';
import 'package:flame/screens/chat/state/message_thread_provider.dart';

Message _m(String id, String text, {String at = '2026-08-18T10:00:00.000Z'}) =>
    Message.fromJson({
      'id': id, 'sender_id': 'u2', 'text': text, 'created_at': at,
    });

MessageThreadState _state({
  List<Message> messages = const [],
  bool loadingInitial = false,
  bool loadingMore = false,
  String? error,
}) =>
    MessageThreadState(
      messages: messages,
      rows: buildChatRows(messages),
      oldestId: messages.isEmpty ? null : messages.first.id,
      hasMore: false,
      isLoadingInitial: loadingInitial,
      isLoadingMore: loadingMore,
      error: error,
    );

int retries = 0;
final tapped = <String>[];

// MessageBubble hosts a Consumer (_TranslateSection), so the list needs a
// ProviderScope even though it reads nothing itself.
Widget _host(MessageThreadState state) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatMessagesList(
            state: state,
            currentUserId: 'me',
            otherUserName: 'Bea',
            otherUserPhoto: '',
            scrollController: ScrollController(),
            onRetry: () => retries++,
            onMessageLongPress: (m) => tapped.add(m.id),
          ),
        ),
      ),
    );

void main() {
  setUp(() {
    retries = 0;
    tapped.clear();
  });

  testWidgets('loading shows a spinner and neither error nor empty',
      (tester) async {
    await tester.pumpWidget(_host(_state(loadingInitial: true)));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(ChatErrorWidget), findsNothing);
    expect(find.byType(ConversationEmptyState), findsNothing);
  });

  testWidgets('an error on an empty thread shows the error, never the empty state',
      (tester) async {
    await tester.pumpWidget(_host(_state(error: 'offline')));
    await tester.pumpAndSettle();

    expect(find.byType(ChatErrorWidget), findsOneWidget);
    expect(find.byType(ConversationEmptyState), findsNothing);
    expect(find.text('offline'), findsOneWidget);
  });

  testWidgets('the error offers a retry that calls back', (tester) async {
    await tester.pumpWidget(_host(_state(error: 'offline')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retry'));
    await tester.pump();

    expect(retries, 1);
  });

  testWidgets('loaded and empty shows the empty state', (tester) async {
    await tester.pumpWidget(_host(_state()));
    await tester.pumpAndSettle();

    expect(find.byType(ConversationEmptyState), findsOneWidget);
    expect(find.byType(ChatErrorWidget), findsNothing);
    expect(find.textContaining('Bea'), findsOneWidget);
  });

  testWidgets('every bubble carries a ValueKey of its message id',
      (tester) async {
    await tester.pumpWidget(
        _host(_state(messages: [_m('m1', 'a'), _m('m2', 'b')])));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('m1')), findsOneWidget);
    expect(find.byKey(const ValueKey('m2')), findsOneWidget);
  });

  testWidgets('a day boundary renders a separator', (tester) async {
    await tester.pumpWidget(_host(_state(messages: [
      _m('m1', 'a', at: '2026-08-17T10:00:00.000Z'),
      _m('m2', 'b', at: '2026-08-18T10:00:00.000Z'),
    ])));
    await tester.pumpAndSettle();

    expect(find.byType(DateSeparatorChip), findsNWidgets(2));
  });

  testWidgets('a failed older page shows an inline retry, not a spinner',
      (tester) async {
    await tester.pumpWidget(
        _host(_state(messages: [_m('m1', 'a')], error: 'offline')));
    await tester.pumpAndSettle();

    // The full-surface error only covers an empty thread; without this row the
    // failure would be entirely silent.
    expect(find.byType(ChatErrorWidget), findsNothing);
    expect(find.byIcon(Icons.refresh), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('a loading older page shows a spinner above the messages',
      (tester) async {
    await tester.pumpWidget(
        _host(_state(messages: [_m('m1', 'a')], loadingMore: true)));
    // pump, not pumpAndSettle: the spinner animates forever and would time out.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.byKey(const ValueKey('m1')), findsOneWidget);
  });

  testWidgets('the list dismisses the keyboard on drag', (tester) async {
    await tester.pumpWidget(_host(_state(messages: [_m('m1', 'a')])));
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag);
  });

  testWidgets('a long press reports the message it was on', (tester) async {
    await tester.pumpWidget(
        _host(_state(messages: [_m('m1', 'a'), _m('m2', 'b')])));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('b'));
    await tester.pump();

    expect(tapped, ['m2']);
  });
}
