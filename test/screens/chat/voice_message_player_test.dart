import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/screens/chat/widgets/voice_message_player.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    ),
  );
}

void main() {
  testWidgets('renders a play control and the fallback duration when idle',
      (tester) async {
    await _pump(
      tester,
      const VoiceMessagePlayer(
        url: 'https://example.com/voice.m4a',
        fallbackDuration: 65,
        isMe: false,
      ),
    );

    // Idle: shows play (not pause), the total duration, a progress bar, and
    // never instantiates the audio plugin (lazy in the provider).
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders for the current user (isMe) without error',
      (tester) async {
    await _pump(
      tester,
      const VoiceMessagePlayer(
        url: 'https://example.com/voice.m4a',
        fallbackDuration: 5,
        isMe: true,
      ),
    );

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text('0:05'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
