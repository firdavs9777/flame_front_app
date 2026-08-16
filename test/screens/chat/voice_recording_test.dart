import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/screens/chat/voice_recording.dart';
import 'package:flame/screens/chat/widgets/chat_input.dart';

// Voice messages had a backend route, a player that renders incoming ones, the
// `record` package in pubspec and the iOS microphone permission already
// declared — and no way to record one. This pins the composer half.
//
// The layout follows BananaTalk's chat_input_bar.dart: one slot on the right
// that is a mic while the field is empty and a send button once there is text,
// rather than two buttons competing for the same corner.
void main() {
  group('formatRecordingTime', () {
    test('reads as mm:ss', () {
      expect(formatRecordingTime(Duration.zero), '0:00');
      expect(formatRecordingTime(const Duration(seconds: 7)), '0:07');
      expect(formatRecordingTime(const Duration(seconds: 65)), '1:05');
      expect(formatRecordingTime(const Duration(minutes: 12, seconds: 3)), '12:03');
    });

    test('a long recording keeps counting rather than wrapping', () {
      expect(formatRecordingTime(const Duration(hours: 1, minutes: 1)), '61:00');
    });
  });

  group('ChatInput idle state', () {
    Widget host({
      required TextEditingController controller,
      VoidCallback? onStartRecording,
    }) => MaterialApp(
      home: Scaffold(
        body: ChatInput(
          controller: controller,
          isSending: false,
          onSend: () {},
          onStartRecording: onStartRecording,
        ),
      ),
    );

    testWidgets('offers the mic while the field is empty', (tester) async {
      await tester.pumpWidget(host(
        controller: TextEditingController(),
        onStartRecording: () {},
      ));

      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.byIcon(Icons.send), findsNothing);
    });

    testWidgets('swaps to send as soon as there is text', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(host(
        controller: controller,
        onStartRecording: () {},
      ));

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();

      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsNothing,
          reason: 'one slot, not two buttons fighting for the same corner');
    });

    testWidgets('whitespace alone is not text', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(host(
        controller: controller,
        onStartRecording: () {},
      ));

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      expect(find.byIcon(Icons.mic), findsOneWidget,
          reason: 'sending spaces is never the intent');
    });

    testWidgets('falls back to send when recording is not offered', (tester) async {
      // onStartRecording null means the caller cannot record; the composer must
      // still work rather than render a mic that does nothing.
      await tester.pumpWidget(host(controller: TextEditingController()));

      expect(find.byIcon(Icons.mic), findsNothing);
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('tapping the mic starts a recording', (tester) async {
      var started = 0;
      await tester.pumpWidget(host(
        controller: TextEditingController(),
        onStartRecording: () => started++,
      ));

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();

      expect(started, 1);
    });
  });

  group('ChatInput recording state', () {
    Widget recording({
      Duration elapsed = const Duration(seconds: 3),
      VoidCallback? onCancel,
      VoidCallback? onSend,
    }) => MaterialApp(
      home: Scaffold(
        body: ChatInput(
          controller: TextEditingController(),
          isSending: false,
          onSend: () {},
          onStartRecording: () {},
          isRecording: true,
          recordingElapsed: elapsed,
          onCancelRecording: onCancel ?? () {},
          onSendRecording: onSend ?? () {},
        ),
      ),
    );

    testWidgets('replaces the composer with a live timer', (tester) async {
      await tester.pumpWidget(recording(elapsed: const Duration(seconds: 42)));

      expect(find.text('0:42'), findsOneWidget);
      expect(find.byType(TextField), findsNothing,
          reason: 'typing mid-recording is not a thing the user can do');
    });

    testWidgets('offers both discard and send', (tester) async {
      var cancelled = 0;
      var sent = 0;
      await tester.pumpWidget(recording(
        onCancel: () => cancelled++,
        onSend: () => sent++,
      ));

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      expect(cancelled, 1);

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      expect(sent, 1,
          reason: 'a recording you cannot discard is a recording you must send');
    });
  });
}
