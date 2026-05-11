enum SocketStatus { disconnected, connecting, connected, reconnecting, failed }

class SocketState {
  final SocketStatus status;
  final String? userId;
  final String? sid;
  final DateTime? sinceLastChange;
  const SocketState({required this.status, this.userId, this.sid, this.sinceLastChange});

  SocketState copy({SocketStatus? status, String? userId, String? sid, DateTime? sinceLastChange}) =>
      SocketState(
        status: status ?? this.status,
        userId: userId ?? this.userId,
        sid: sid ?? this.sid,
        sinceLastChange: sinceLastChange ?? this.sinceLastChange,
      );
}
