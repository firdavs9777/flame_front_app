import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/realtime/socket_client.dart';
import 'package:flame/realtime/socket_state.dart';

void main() {
  group('SocketClient state', () {
    test('starts disconnected', () {
      final client = SocketClient();
      expect(client.state.status, SocketStatus.disconnected);
    });
  });

  group('emitWithAckTimeoutVia (testable helper)', () {
    test('completes with ack payload', () async {
      final result = await SocketClient.emitWithAckTimeoutVia(
        (event, data, ack) => Future.delayed(
          const Duration(milliseconds: 10), () => ack({'ok': true})),
        'foo', const {},
        timeout: const Duration(seconds: 1),
      );
      expect(result, {'ok': true});
    });

    test('times out when ack never invoked', () async {
      expect(
        () => SocketClient.emitWithAckTimeoutVia(
          (event, data, ack) {/* never acks */},
          'foo', const {},
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
