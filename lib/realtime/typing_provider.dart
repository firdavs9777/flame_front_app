import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'constants.dart';
import 'providers.dart';

final typingProvider =
    StateNotifierProvider.family<TypingNotifier, bool, String>(
        (ref, conversationId) => TypingNotifier(ref, conversationId));

class TypingNotifier extends StateNotifier<bool> {
  final Ref ref;
  final String conversationId;
  Timer? _idleTimer;

  TypingNotifier(this.ref, this.conversationId) : super(false) {
    final socket = ref.read(socketClientProvider);
    socket.eventStream.listen((tuple) {
      final event = tuple.$1;
      final data = tuple.$2;
      if (event != RtEvents.typingUpdate || data is! Map) return;
      if (data['conversation_id'] != conversationId) return;
      state = data['is_typing'] == true;
      _idleTimer?.cancel();
      if (state) {
        _idleTimer = Timer(const Duration(seconds: 5), () => state = false);
      }
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }
}
