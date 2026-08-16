import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/env.dart';
import 'socket_state.dart';

class SocketClient {
  io.Socket? _socket;
  SocketState _state = const SocketState(status: SocketStatus.disconnected);
  final _stateCtl = StreamController<SocketState>.broadcast();
  final _eventCtl = StreamController<(String, dynamic)>.broadcast();

  SocketState get state => _state;
  Stream<SocketState> get stateStream => _stateCtl.stream;
  Stream<(String, dynamic)> get eventStream => _eventCtl.stream;

  static Future<dynamic> emitWithAckTimeoutVia(
    void Function(String event, dynamic data, void Function(dynamic) ack) emit,
    String event,
    dynamic data, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    final completer = Completer<dynamic>();
    emit(event, data, (resp) {
      if (!completer.isCompleted) completer.complete(resp);
    });
    return completer.future.timeout(
      timeout,
      onTimeout: () => throw TimeoutException('ack'),
    );
  }

  /// Socket.IO namespace the Flame realtime chat lives on.
  ///
  /// The server is shared with BananaTalk and FitBowl: `flameSocket.js` isolates
  /// Flame onto `io.of('/flame')`, so connecting to the default namespace would
  /// silently join BananaTalk's and receive none of Flame's events.
  static const _namespace = '/flame';

  void connect({required String token, required String deviceId}) {
    _setState(const SocketState(status: SocketStatus.connecting));
    final socket = io.io(
      '${EnvConfig.current.wsBase}$_namespace',
      io.OptionBuilder()
          .setTransports(['websocket'])
          // No setPath: the server constructs `new Server(server, {...})`
          // without a `path` option, so it serves the Socket.IO default
          // (/socket.io). The previous '/ws/socket.io' matched nothing and the
          // handshake could never complete.
          .setAuth({'token': token, 'device_id': deviceId})
          .enableReconnection()
          .setReconnectionAttempts(double.maxFinite.toInt())
          .build(),
    );
    socket.onConnect((_) {
      _setState(
        _state.copy(
          status: SocketStatus.connected,
          sinceLastChange: DateTime.now(),
        ),
      );
    });
    socket.onDisconnect((_) {
      _setState(_state.copy(status: SocketStatus.reconnecting));
    });
    socket.onConnectError((e) {
      _setState(_state.copy(status: SocketStatus.failed));
    });
    socket.onAny((event, data) => _eventCtl.add((event, data)));
    _socket = socket;
  }

  Future<void> disconnect() async {
    _socket?.dispose();
    _socket = null;
    _setState(const SocketState(status: SocketStatus.disconnected));
  }

  void emit(String event, dynamic data) => _socket?.emit(event, data);

  Future<dynamic> emitWithAckTimeout(
    String event,
    dynamic data, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    final socket = _socket;
    if (socket == null) return Future.error(StateError('no socket'));
    return emitWithAckTimeoutVia(
      (e, d, ack) => socket.emitWithAck(e, d, ack: ack),
      event,
      data,
      timeout: timeout,
    );
  }

  void _setState(SocketState s) {
    _state = s;
    _stateCtl.add(s);
  }

  void dispose() {
    _socket?.dispose();
    _stateCtl.close();
    _eventCtl.close();
  }
}
