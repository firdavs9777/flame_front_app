import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flame/services/api_client.dart';

/// WebSocket events that can be sent to the server
class WebSocketEvent {
  static const String ping = 'ping';
  static const String typing = 'typing';
  static const String stopTyping = 'stop_typing';
  static const String messageRead = 'message_read';
  static const String recordingVoice = 'recording_voice';
}

/// WebSocket events received from the server
class WebSocketServerEvent {
  static const String pong = 'pong';
  static const String newMessage = 'new_message';
  static const String newMatch = 'new_match';
  static const String userTyping = 'user_typing';
  static const String userStopTyping = 'user_stop_typing';
  static const String messageStatus = 'message_status';
  static const String userOnline = 'user_online';
  static const String userOffline = 'user_offline';
  // New events for reactions, edits, pins
  static const String messageEdited = 'message_edited';
  static const String messageDeleted = 'message_deleted';
  static const String reactionAdded = 'reaction_added';
  static const String reactionRemoved = 'reaction_removed';
  static const String messagePinned = 'message_pinned';
  static const String messageUnpinned = 'message_unpinned';
  static const String userRecordingVoice = 'user_recording_voice';
}

typedef WebSocketEventCallback = void Function(Map<String, dynamic> data);

class WebSocketService {
  static const String _wsBaseUrl = 'wss://flame.banatalk.com/ws';

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  static const Duration _pingInterval = Duration(seconds: 30);
  static const Duration _baseReconnectDelay = Duration(seconds: 1);

  bool _isConnected = false;
  bool _isConnecting = false;
  String? _accessToken;

  // Event listeners
  final Map<String, Set<WebSocketEventCallback>> _listeners = {};

  // Singleton pattern
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  bool get isConnected => _isConnected;

  /// Connect to WebSocket server
  Future<bool> connect() async {
    if (_isConnected || _isConnecting) return _isConnected;

    _isConnecting = true;

    // Get access token from ApiClient
    final apiClient = ApiClient();
    _accessToken = apiClient.accessToken;

    if (_accessToken == null) {
      debugPrint('WebSocket: No access token available');
      _isConnecting = false;
      return false;
    }

    try {
      final wsUrl = Uri.parse('$_wsBaseUrl?token=$_accessToken');
      debugPrint('WebSocket: Connecting to $wsUrl');

      _channel = WebSocketChannel.connect(wsUrl);

      // Wait for connection to be ready
      await _channel!.ready;

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;

      debugPrint('WebSocket: Connected successfully');

      // Listen to incoming messages
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      // Start ping interval
      _startPingTimer();

      return true;
    } catch (e) {
      debugPrint('WebSocket: Connection failed - $e');
      _isConnected = false;
      _isConnecting = false;
      _attemptReconnect();
      return false;
    }
  }

  /// Disconnect from WebSocket server
  void disconnect() {
    debugPrint('WebSocket: Disconnecting...');
    _stopPingTimer();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close(1000, 'User disconnect');
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _reconnectAttempts = 0;
  }

  /// Send an event to the server
  void send(String event, [Map<String, dynamic>? data]) {
    if (!_isConnected || _channel == null) {
      debugPrint('WebSocket: Cannot send - not connected');
      return;
    }

    final message = jsonEncode({
      'event': event,
      'data': data ?? {},
    });

    debugPrint('WebSocket: Sending - $message');
    _channel!.sink.add(message);
  }

  /// Send typing indicator
  void sendTyping(String conversationId) {
    send(WebSocketEvent.typing, {'conversation_id': conversationId});
  }

  /// Send stop typing indicator
  void sendStopTyping(String conversationId) {
    send(WebSocketEvent.stopTyping, {'conversation_id': conversationId});
  }

  /// Send message read event
  void sendMessageRead(String conversationId, List<String> messageIds) {
    send(WebSocketEvent.messageRead, {
      'conversation_id': conversationId,
      'message_ids': messageIds,
    });
  }

  /// Send recording voice indicator
  void sendRecordingVoice(String conversationId) {
    send(WebSocketEvent.recordingVoice, {'conversation_id': conversationId});
  }

  /// Add event listener
  void on(String event, WebSocketEventCallback callback) {
    _listeners[event] ??= {};
    _listeners[event]!.add(callback);
  }

  /// Remove event listener
  void off(String event, WebSocketEventCallback callback) {
    _listeners[event]?.remove(callback);
  }

  /// Remove all listeners for an event
  void offAll(String event) {
    _listeners.remove(event);
  }

  /// Handle incoming message
  void _onMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final event = data['event'] as String?;
      final eventData = data['data'] as Map<String, dynamic>? ?? {};

      debugPrint('WebSocket: Received - event: $event');

      if (event == null) return;

      // Emit to listeners
      _emit(event, eventData);
    } catch (e) {
      debugPrint('WebSocket: Failed to parse message - $e');
    }
  }

  /// Handle WebSocket error
  void _onError(dynamic error) {
    debugPrint('WebSocket: Error - $error');
    _isConnected = false;
    _emit('error', {'error': error.toString()});
    _attemptReconnect();
  }

  /// Handle WebSocket close
  void _onDone() {
    debugPrint('WebSocket: Connection closed');
    _isConnected = false;
    _stopPingTimer();

    // Check close code
    final closeCode = _channel?.closeCode;
    debugPrint('WebSocket: Close code - $closeCode');

    if (closeCode == 4001) {
      // Unauthorized - token expired
      _emit('auth_error', {'code': 4001});
    } else {
      _attemptReconnect();
    }
  }

  /// Emit event to listeners
  void _emit(String event, Map<String, dynamic> data) {
    final callbacks = _listeners[event];
    if (callbacks != null) {
      for (final callback in callbacks) {
        try {
          callback(data);
        } catch (e) {
          debugPrint('WebSocket: Listener error - $e');
        }
      }
    }
  }

  /// Start ping timer to keep connection alive
  void _startPingTimer() {
    _stopPingTimer();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      send(WebSocketEvent.ping);
    });
  }

  /// Stop ping timer
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  /// Attempt to reconnect with exponential backoff
  void _attemptReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('WebSocket: Max reconnect attempts reached');
      _emit('reconnect_failed', {});
      return;
    }

    _reconnectAttempts++;
    final delay = _baseReconnectDelay * (1 << (_reconnectAttempts - 1));

    debugPrint('WebSocket: Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      connect();
    });
  }
}
