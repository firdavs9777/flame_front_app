import 'dart:developer' as developer;

import 'package:socket_io_client/socket_io_client.dart' as sio;

import '../config/env.dart';
import '../models/models.dart';

/// Realtime chat transport for the Flame backend's isolated `/flame`
/// Socket.IO namespace.
///
/// This is a focused, standalone service — it does NOT touch the raw
/// `WebSocketService` (`lib/services/websocket_service.dart`) or the dead
/// `lib/realtime/*` stack. Callers own the socket's lifecycle: construct
/// with a token, call [connect], wire the callbacks, and call [dispose]
/// when the owning widget goes away.
///
/// Every callback and socket call is guarded so a malformed payload or a
/// transport hiccup never throws past this service.
class FlameSocketService {
  final String token;

  sio.Socket? _socket;

  /// Fired when the server pushes a new message (`message:new`).
  /// [conversationId] is passed alongside the parsed [Message] since
  /// `Message` (shared with the REST paths) has no `conversationId` field of
  /// its own — callers use it to filter to the currently open thread.
  void Function(Message message, String? conversationId)? onMessageNew;

  /// Fired when a message is edited (`message:edited`). Payload is the full
  /// updated [Message] (with `is_edited`/`edited_at` set); [conversationId]
  /// is passed alongside it the same way as [onMessageNew].
  void Function(Message message, String? conversationId)? onMessageEdited;

  /// Fired when a message is deleted (`message:deleted`). Payload is the
  /// tombstoned [Message] (with `is_deleted` set); [conversationId] is
  /// passed alongside it the same way as [onMessageNew].
  void Function(Message message, String? conversationId)? onMessageDeleted;

  /// Fired when the other participant starts typing (`typing`).
  /// Args: (fromUserId, conversationId).
  void Function(String fromUserId, String conversationId)? onTyping;

  /// Fired when the other participant stops typing (`stopTyping`).
  void Function(String fromUserId, String conversationId)? onStopTyping;

  /// Fired when the other participant reads messages (`read`).
  /// Args: (byUserId, conversationId).
  void Function(String byUserId, String conversationId)? onRead;

  FlameSocketService({required this.token});

  bool get isConnected => _socket?.connected ?? false;

  /// Opens the socket connection to the `/flame` namespace. Safe to call
  /// more than once — subsequent calls are no-ops while a socket already
  /// exists.
  void connect() {
    if (_socket != null) return;

    try {
      final url = '${EnvConfig.current.wsBase}/flame';
      final socket = sio.io(
        url,
        sio.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': token})
            .disableAutoConnect()
            .build(),
      );
      _socket = socket;

      socket
        ..onConnect((_) => _log('connected'))
        ..onDisconnect((_) => _log('disconnected'))
        ..onConnectError((err) => _log('connect_error: $err'))
        ..onError((err) => _log('error: $err'))
        ..on('message:new', _handleMessageNew)
        ..on('message:edited', _handleMessageEdited)
        ..on('message:deleted', _handleMessageDeleted)
        ..on('typing', _handleTyping)
        ..on('stopTyping', _handleStopTyping)
        ..on('read', _handleRead);

      socket.connect();
    } catch (e, st) {
      _log('connect() threw: $e\n$st');
    }
  }

  void _handleMessageNew(dynamic data) {
    try {
      if (data is Map) {
        final json = Map<String, dynamic>.from(data);
        final message = Message.fromJson(json);
        final conversationId = json['conversation_id']?.toString();
        onMessageNew?.call(message, conversationId);
      }
    } catch (e) {
      _log('failed to handle message:new: $e');
    }
  }

  void _handleMessageEdited(dynamic data) {
    try {
      if (data is Map) {
        final json = Map<String, dynamic>.from(data);
        final message = Message.fromJson(json);
        final conversationId = json['conversation_id']?.toString();
        onMessageEdited?.call(message, conversationId);
      }
    } catch (e) {
      _log('failed to handle message:edited: $e');
    }
  }

  void _handleMessageDeleted(dynamic data) {
    try {
      if (data is Map) {
        final json = Map<String, dynamic>.from(data);
        final message = Message.fromJson(json);
        final conversationId = json['conversation_id']?.toString();
        onMessageDeleted?.call(message, conversationId);
      }
    } catch (e) {
      _log('failed to handle message:deleted: $e');
    }
  }

  void _handleTyping(dynamic data) {
    try {
      if (data is Map) {
        final from = data['from']?.toString();
        final conversationId = data['conversation_id']?.toString();
        if (from != null && conversationId != null) {
          onTyping?.call(from, conversationId);
        }
      }
    } catch (e) {
      _log('failed to handle typing: $e');
    }
  }

  void _handleStopTyping(dynamic data) {
    try {
      if (data is Map) {
        final from = data['from']?.toString();
        final conversationId = data['conversation_id']?.toString();
        if (from != null && conversationId != null) {
          onStopTyping?.call(from, conversationId);
        }
      }
    } catch (e) {
      _log('failed to handle stopTyping: $e');
    }
  }

  void _handleRead(dynamic data) {
    try {
      if (data is Map) {
        final by = data['by']?.toString();
        final conversationId = data['conversation_id']?.toString();
        if (by != null && conversationId != null) {
          onRead?.call(by, conversationId);
        }
      }
    } catch (e) {
      _log('failed to handle read: $e');
    }
  }

  void emitTyping(String to, String conversationId) {
    _emit('typing', {'to': to, 'conversation_id': conversationId});
  }

  void emitStopTyping(String to, String conversationId) {
    _emit('stopTyping', {'to': to, 'conversation_id': conversationId});
  }

  void emitMarkRead(String to, String conversationId) {
    _emit('markRead', {'to': to, 'conversation_id': conversationId});
  }

  void _emit(String event, Map<String, dynamic> payload) {
    try {
      _socket?.emit(event, payload);
    } catch (e) {
      _log('failed to emit $event: $e');
    }
  }

  /// Tears down the socket and clears all listeners. Safe to call multiple
  /// times.
  void dispose() {
    try {
      _socket?.dispose();
    } catch (e) {
      _log('dispose() threw: $e');
    } finally {
      _socket = null;
    }
  }

  void _log(String message) {
    developer.log(message, name: 'FlameSocketService');
  }
}
