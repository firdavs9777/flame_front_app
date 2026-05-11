import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../socket_state.dart';
import '../providers.dart';
import '../constants.dart';

class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(socketStateProvider).valueOrNull;
    if (state == null || state.status == SocketStatus.connected) {
      return const SizedBox.shrink();
    }
    final stuckOffline = state.sinceLastChange != null &&
        DateTime.now().difference(state.sinceLastChange!) > RtTimeouts.offlineBannerAfter;
    final isOffline = stuckOffline || state.status == SocketStatus.failed;
    return Container(
      width: double.infinity,
      color: isOffline ? Colors.red.shade400 : Colors.amber.shade400,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Text(
          isOffline ? 'Offline' : 'Reconnecting…',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    );
  }
}
