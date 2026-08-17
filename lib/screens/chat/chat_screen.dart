import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/config/env.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/services/flame_socket_service.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/screens/profile/profile_detail_screen.dart';
import 'package:flame/widgets/smart_image.dart';
import 'package:flame/screens/chat/chat_attachments.dart';
import 'package:flame/screens/chat/chat_rows.dart';
import 'package:flame/screens/chat/widgets/sticker_panel.dart';
import 'package:flame/services/chat_service.dart' show PinnedMessage;
import 'package:flame/screens/chat/voice_recording.dart';
import 'package:flame/screens/chat/widgets/widgets.dart';

/// How often to poll for new messages while a thread is open. This is a REST
/// stand-in for realtime delivery — only runs when
/// `EnvConfig.current.realtimeEnabled` is false (which is always, for now,
/// since the backend has no chat socket).
const Duration _pollInterval = Duration(seconds: 4);

class ChatScreen extends ConsumerStatefulWidget {
  final Conversation conversation;

  const ChatScreen({super.key, required this.conversation});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isSending = false;
  bool _isLoadingMessages = false;
  bool _hasMoreMessages = true;
  List<Message> _messages = [];

  Message? _replyingTo;
  Timer? _pollTimer;

  /// The caller's pinned messages. Loaded on open — before this the backend had
  /// no way to report them, so a bar would have been empty on entry and
  /// vanished on reopen.
  List<PinnedMessage> _pinned = [];

  /// Mirrors the conversation's is_muted, kept locally so the menu reflects a
  /// toggle immediately rather than waiting for a list refetch.
  late bool _isMuted = widget.conversation.isMuted;

  /// The app-level connection, cached (not its socket) so every emit site
  /// reads `.socket` fresh. `RealtimeConnection.start()` replaces the socket
  /// on a token refresh (disposing the old one); caching the socket itself
  /// would leave emits pointed at a disposed instance after that happens
  /// mid-session, silently turning `emitTyping`/`emitStopTyping`/`emitMarkRead`
  /// into no-ops (`FlameSocketService`'s emit guards are `_socket?.emit`, so
  /// nothing throws or logs). The connection object itself is long-lived and
  /// outlives any such swap.
  RealtimeConnection? _realtime;
  final List<StreamSubscription<void>> _realtimeSubs = [];

  // ==================== Typing indicator state (flame socket) ====================

  /// Whether *we* are currently signaling "typing" to the other participant.
  /// Only used to gate emits so we send `typing` once on the false→true
  /// transition rather than on every keystroke.
  bool _isTyping = false;

  /// Whether the other participant is currently typing, per the flame socket
  /// (`typing`/`stopTyping` events). This is the only source of truth: the
  /// legacy `typingUsersProvider` was driven by a WebSocketService that
  /// connected to a nonexistent endpoint, and has been removed.
  /// paths can coexist without interfering with each other.
  bool _isOtherUserTypingFlame = false;

  /// Restarted on every outgoing keystroke; fires `stopTyping` after 3s of
  /// idle.
  Timer? _typingIdleTimer;

  /// Safety net for the incoming indicator: restarted on every `typing`
  /// event we receive, hides the indicator after 5s in case a `stopTyping`
  /// is dropped.
  Timer? _typingSafetyTimer;

  // ==================== Presence state (flame socket) ====================

  /// Live online state pushed by the flame socket (`presence` /
  /// `presence:bulk`), keyed by user id. Seeded from
  /// `conversation.otherUser.isOnline` (the REST snapshot) so the dot has a
  /// reasonable value before any socket event arrives; updated in place as
  /// `presence`/`presence:bulk` events come in. Absent chat-enabled/socket
  /// data just means the seeded value (possibly `false`) is shown — never a
  /// synthesized "offline" state.
  final Map<String, bool> _presence = {};

  @override
  void initState() {
    super.initState();
    _presence[widget.conversation.otherUser.id] =
        widget.conversation.otherUser.isOnline;
    _loadInitialMessages();
    _scrollController.addListener(_onScroll);
    _startPolling();
    _connectFlameSocket();
    _loadPinned();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _recordingTimer?.cancel();
    // Fire-and-forget: dispose() cannot await, and a dangling recorder would
    // hold the microphone after the screen is gone.
    _recorder?.cancel().then((_) => _recorder?.dispose()).catchError((_) {});
    _typingIdleTimer?.cancel();
    _typingSafetyTimer?.cancel();
    if (_isTyping) {
      _realtime?.socket?.emitStopTyping(
        widget.conversation.otherUser.id,
        widget.conversation.id,
      );
    }
    // The connection is app-level and outlives this screen: cancel our
    // subscriptions instead of disposing it. Disposing it here would kill the
    // conversation list's realtime and the unread badge along with the chat.
    for (final s in _realtimeSubs) {
      s.cancel();
    }
    _realtimeSubs.clear();
    _realtime = null;
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==================== Data Loading ====================

  void _onScroll() {
    if (_scrollController.position.pixels ==
        _scrollController.position.minScrollExtent) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadInitialMessages() async {
    setState(() => _isLoadingMessages = true);

    final chatService = ref.read(chatServiceProvider);
    final result = await chatService.getMessages(widget.conversation.id);

    if (mounted) {
      setState(() {
        _isLoadingMessages = false;
        if (result.success && result.data != null) {
          // Backend returns newest-first; reverse to oldest-first for display
          // (oldest at top, newest at bottom).
          _messages = result.data!.messages.reversed.toList();
          _hasMoreMessages = result.data!.hasMore;
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      _markMessagesAsRead();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMessages || !_hasMoreMessages || _messages.isEmpty) return;

    setState(() => _isLoadingMessages = true);

    final chatService = ref.read(chatServiceProvider);
    final result = await chatService.getMessages(
      widget.conversation.id,
      offset: _messages.length,
    );

    if (mounted) {
      // Preserve the visual scroll position when older messages are
      // prepended above the currently visible content.
      final hasScrollClient = _scrollController.hasClients;
      final oldExtent = hasScrollClient
          ? _scrollController.position.maxScrollExtent
          : 0.0;
      final oldOffset = hasScrollClient ? _scrollController.offset : 0.0;

      setState(() {
        _isLoadingMessages = false;
        if (result.success && result.data != null) {
          final existingIds = _messages.map((m) => m.id).toSet();
          // Backend returns this page newest-first; reverse to oldest-first
          // so older messages read top-to-bottom before being prepended.
          final olderMessages = result.data!.messages.reversed
              .where((m) => !existingIds.contains(m.id))
              .toList();
          _messages = [...olderMessages, ..._messages];
          _hasMoreMessages = result.data!.hasMore;
        }
      });

      if (hasScrollClient) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            final newExtent = _scrollController.position.maxScrollExtent;
            _scrollController.jumpTo(oldOffset + (newExtent - oldExtent));
          }
        });
      }
    }
  }

  Future<void> _refreshMessages() async {
    final chatService = ref.read(chatServiceProvider);
    final result = await chatService.getMessages(widget.conversation.id);

    if (!mounted) return;
    if (!result.success || result.data == null) return;

    // Merge-append rather than replace, so history loaded further up (via
    // _loadMoreMessages) isn't collapsed by this newest-page fetch.
    setState(() {
      final existingIds = _messages.map((m) => m.id).toSet();
      final newMessages = result.data!.messages.reversed
          .where((m) => !existingIds.contains(m.id))
          .toList();
      _messages = [..._messages, ...newMessages];
      _hasMoreMessages = result.data!.hasMore;
    });
  }

  // ==================== Polling ====================

  /// Starts the REST-polling fallback used while realtime delivery is
  /// unavailable. Cancelled in [dispose].
  void _startPolling() {
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!EnvConfig.current.realtimeEnabled) {
        _pollForNewMessages();
      }
    });
  }

  // ==================== Realtime (Flame socket) ====================

  /// Subscribes this thread to the app-level realtime connection.
  ///
  /// It used to construct its own [FlameSocketService], which meant two sockets
  /// per user whenever a chat was open: the server re-checks blocks on every
  /// delivery, so the duplicate doubled that lookup and the presence fan-out
  /// for nothing. The connection is held in [_realtime] — not its socket —
  /// because this screen emits through it (typing, read receipts) — but it
  /// does not own it and must never dispose it.
  ///
  /// Caching the connection rather than `conn.socket` matters for two reasons:
  ///
  /// 1. The socket can be null at mount (connection not up yet) or can be
  ///    swapped mid-session (`RealtimeConnection.start` disposes the old
  ///    socket and builds a new one on a token refresh). Reading `.socket`
  ///    fresh at each emit site means a not-yet-connected mount still
  ///    subscribes to every stream (no early return), and a mid-session swap
  ///    never leaves an emit pointed at a disposed socket.
  /// 2. Subscribing through streams rather than assigning the socket's
  ///    callbacks matters: those fields are single-assignment, so assigning
  ///    them here would silently steal every push from the conversation list
  ///    and freeze the unread badge for other threads while this one is open.
  void _connectFlameSocket() {
    if (!EnvConfig.current.chatEnabled) return;

    final conn = ref.read(realtimeConnectionProvider);
    _realtime = conn;

    // Opening a conversation is a refresh point for the connection, and it has
    // to stay one. socket.io replays the token it was constructed with on every
    // automatic reconnect, so a socket built before ApiClient last refreshed is
    // authenticated with a string the server will never accept again — and
    // nothing in the app-level path notices, because a refresh never touches
    // authProvider. The pre-B1 code got this for free by building a fresh
    // socket from `ApiClient().accessToken` on every mount; this restores it
    // without going back to a socket per screen. `start` no-ops when the token
    // is unchanged, so the common case costs nothing.
    applySessionStatus(
      conn,
      AuthStatus.authenticated,
      () => ApiClient().accessToken,
    );

    _realtimeSubs.addAll([
      conn.messageNew.listen((e) => _onSocketMessageNew(e.message, e.conversationId)),
      conn.messageEdited.listen((e) => _onSocketMessageEdited(e.message, e.conversationId)),
      conn.messageDeleted.listen((e) => _onSocketMessageDeleted(e.message, e.conversationId)),
      conn.typing.listen((e) => _onSocketTyping(e.fromUserId, e.conversationId)),
      conn.stopTyping.listen((e) => _onSocketStopTyping(e.fromUserId, e.conversationId)),
      conn.presence.listen((e) => _onSocketPresence(e.userId, e.online)),
      conn.presenceBulk.listen(_onSocketPresenceBulk),
    ]);
  }

  /// Handles a `message:new` push for this open thread. Reuses the same
  /// merge-append + de-dupe pattern as [_pollForNewMessages]: only append if
  /// the id isn't already present, keep newest at the bottom, and respect
  /// the scroll-pin so an open thread that's been scrolled up doesn't jump.
  void _onSocketMessageNew(Message message, String? conversationId) {
    if (conversationId != widget.conversation.id) return;
    if (!mounted) return;
    if (_messages.any((m) => m.id == message.id)) return;

    final shouldPinToBottom = _isScrolledToBottom();

    setState(() {
      _messages = [..._messages, message];
    });

    // This thread is open and being read, so the server-side unread bump is
    // already stale for us. `clearUnread` is local-only; the REST mark-read
    // that tells the server runs on its own path.
    ref.read(conversationsProvider.notifier).clearUnread(widget.conversation.id);

    _markMessagesAsRead();

    if (shouldPinToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom(animated: true);
      });
    }
  }

  /// Handles a `message:edited` push for this open thread: replaces the
  /// message in-place by id. Mirrors the guard pattern used elsewhere in
  /// this screen — bail if the event isn't for the open thread or the
  /// widget has since been disposed.
  void _onSocketMessageEdited(Message message, String? conversationId) {
    if (conversationId != widget.conversation.id) return;
    _replaceMessage(message);
  }

  /// Handles a `message:deleted` push for this open thread. The payload is
  /// the tombstoned [Message] (`is_deleted: true`), so this is also a
  /// replace-by-id — [MessageBubble] renders the deleted state itself.
  void _onSocketMessageDeleted(Message message, String? conversationId) {
    if (conversationId != widget.conversation.id) return;
    _replaceMessage(message);
  }

  /// Replaces a message in [_messages] by id, if present. Used by both the
  /// local edit/delete actions and the incoming socket handlers above.
  void _replaceMessage(Message updated) {
    if (!mounted) return;
    if (!_messages.any((m) => m.id == updated.id)) return;

    setState(() {
      _messages = _messages
          .map((m) => m.id == updated.id ? updated : m)
          .toList();
    });
  }

  /// Handles an incoming `typing` push for this open thread. Shows the
  /// [TypingIndicator] and (re)starts a 5s safety timer so a missed
  /// `stopTyping` doesn't leave the indicator stuck forever.
  void _onSocketTyping(String from, String conversationId) {
    if (from != widget.conversation.otherUser.id) return;
    if (conversationId != widget.conversation.id) return;
    if (!mounted) return;

    _typingSafetyTimer?.cancel();
    _typingSafetyTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => _isOtherUserTypingFlame = false);
    });

    if (_isOtherUserTypingFlame) return;
    setState(() => _isOtherUserTypingFlame = true);
  }

  /// Handles an incoming `stopTyping` push for this open thread.
  void _onSocketStopTyping(String from, String conversationId) {
    if (from != widget.conversation.otherUser.id) return;
    if (conversationId != widget.conversation.id) return;
    if (!mounted) return;

    _typingSafetyTimer?.cancel();
    if (!_isOtherUserTypingFlame) return;
    setState(() => _isOtherUserTypingFlame = false);
  }

  /// Handles a `presence` push: updates the one user's online state.
  void _onSocketPresence(String userId, bool online) {
    if (!mounted) return;
    if (_presence[userId] == online) return;
    setState(() => _presence[userId] = online);
  }

  /// Handles a `presence:bulk` push: the server's snapshot of which of this
  /// socket's partners are online right now. Only reconciles user ids
  /// already tracked (i.e. the open thread's partner) plus that partner
  /// explicitly, rather than inventing state for arbitrary user ids we've
  /// never heard of.
  void _onSocketPresenceBulk(List<String> onlineUserIds) {
    if (!mounted) return;
    final onlineSet = onlineUserIds.toSet();
    final partnerId = widget.conversation.otherUser.id;

    setState(() {
      for (final id in _presence.keys.toList()) {
        _presence[id] = onlineSet.contains(id);
      }
      _presence[partnerId] = onlineSet.contains(partnerId);
    });
  }

  /// Called on every [ChatInput] text change. Emits `typing` once on the
  /// false→true transition, then (re)starts a 3s idle timer that emits
  /// `stopTyping` when the user pauses. No-op unless chat is enabled and the
  /// flame socket is connected.
  void _onMessageTextChanged(String text) {
    if (!EnvConfig.current.chatEnabled) return;

    final socket = _realtime?.socket;
    if (socket == null || !socket.isConnected) return;

    if (text.isEmpty) {
      _stopTypingNow();
      return;
    }

    if (!_isTyping) {
      _isTyping = true;
      socket.emitTyping(
        widget.conversation.otherUser.id,
        widget.conversation.id,
      );
    }

    _typingIdleTimer?.cancel();
    _typingIdleTimer = Timer(const Duration(seconds: 3), _stopTypingNow);
  }

  /// Emits `stopTyping` (if we were mid-typing) and cancels the idle timer.
  /// Called on idle timeout, on send, and in [dispose].
  void _stopTypingNow() {
    _typingIdleTimer?.cancel();
    _typingIdleTimer = null;

    if (!_isTyping) return;
    _isTyping = false;

    final socket = _realtime?.socket;
    if (socket != null && socket.isConnected) {
      socket.emitStopTyping(
        widget.conversation.otherUser.id,
        widget.conversation.id,
      );
    }
  }

  bool _isScrolledToBottom() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    // Small threshold so being nearly at the bottom still counts as "at the
    // bottom" for auto-scroll purposes.
    return position.pixels >= position.maxScrollExtent - 40;
  }

  Future<void> _pollForNewMessages() async {
    final chatService = ref.read(chatServiceProvider);
    final result = await chatService.getMessages(widget.conversation.id);

    if (!mounted) return;
    if (!result.success || result.data == null) return;

    final existingIds = _messages.map((m) => m.id).toSet();
    // Backend returns the newest page newest-first; reverse to
    // oldest-first so new messages append to the bottom in order.
    final newMessages = result.data!.messages.reversed
        .where((m) => !existingIds.contains(m.id))
        .toList();

    if (newMessages.isEmpty) return;

    final shouldPinToBottom = _isScrolledToBottom();

    setState(() {
      _messages = [..._messages, ...newMessages];
    });

    _markMessagesAsRead();

    if (shouldPinToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToBottom(animated: true);
      });
    }
  }

  void _markMessagesAsRead() {
    final currentUserId = ref.read(currentUserProvider).valueOrNull?.id ?? '';
    final unreadIds = _messages
        .where(
          (m) => m.status != MessageStatus.read && !m.isSentBy(currentUserId),
        )
        .map((m) => m.id)
        .toList();

    if (unreadIds.isNotEmpty) {
      ref
          .read(conversationsProvider.notifier)
          .markAsRead(widget.conversation.id);
      _realtime?.socket?.emitMarkRead(
        widget.conversation.otherUser.id,
        widget.conversation.id,
      );
    }
  }

  // ==================== Messaging ====================

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    _stopTypingNow();

    // Capture the content and reply target before clearing the input, so
    // they can be restored if the send fails.
    final sentReplyingTo = _replyingTo;
    final replyToId = sentReplyingTo?.id;

    setState(() {
      _isSending = true;
      _replyingTo = null;
    });
    _messageController.clear();

    final error = await ref
        .read(conversationsProvider.notifier)
        .sendMessage(widget.conversation.id, content, replyToId: replyToId);

    if (mounted) {
      setState(() => _isSending = false);

      if (error == null) {
        await _refreshMessages();
        _scrollToBottom(animated: true);
      } else {
        // Restore the user's input and reply target so nothing is lost.
        setState(() {
          _messageController.text = content;
          _messageController.selection = TextSelection.collapsed(
            offset: content.length,
          );
          _replyingTo = sentReplyingTo;
        });
        _showError(error);
      }
    }
  }

  // ==================== Stickers ====================

  /// Opens the sticker panel and sends whatever is tapped.
  ///
  /// A sticker is an emoji in the message text, so this is the ordinary send
  /// path with a type — no upload, no separate endpoint.
  void _openStickerPanel() {
    if (_isSending) return;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => StickerPanel(
        onPick: (emoji) {
          Navigator.pop(sheetContext);
          _sendSticker(emoji);
        },
      ),
    );
  }

  Future<void> _sendSticker(String emoji) async {
    final sentReplyingTo = _replyingTo;

    setState(() {
      _isSending = true;
      _replyingTo = null;
    });

    final error = await ref.read(conversationsProvider.notifier).sendMessage(
          widget.conversation.id,
          emoji,
          type: MessageType.sticker,
          replyToId: sentReplyingTo?.id,
        );

    if (!mounted) return;
    setState(() => _isSending = false);

    if (error == null) {
      await _refreshMessages();
      _scrollToBottom(animated: true);
    } else {
      setState(() => _replyingTo = sentReplyingTo);
      _showError(error);
    }
  }

  // ==================== Pin & mute ====================

  Future<void> _loadPinned() async {
    final result = await ref
        .read(chatServiceProvider)
        .getPinnedMessages(widget.conversation.id);
    if (!mounted || !result.success) return;
    setState(() => _pinned = result.data ?? []);
  }

  Future<void> _pin(Message message) async {
    final result = await ref
        .read(chatServiceProvider)
        .pinMessage(widget.conversation.id, message.id);
    if (!mounted) return;

    if (!result.success) {
      _showError(result.error ?? 'Could not pin');
      return;
    }
    // The endpoint answers with the caller's FULL pin list, so replace rather
    // than append — merging would drift from the server's view.
    setState(() => _pinned = result.data ?? []);
  }

  Future<void> _unpin(String messageId) async {
    final result = await ref
        .read(chatServiceProvider)
        .unpinMessage(widget.conversation.id, messageId);
    if (!mounted) return;

    if (!result.success) {
      _showError(result.error ?? 'Could not unpin');
      return;
    }
    setState(() => _pinned.removeWhere((p) => p.messageId == messageId));
  }

  /// Scrolls to a pinned message if it is loaded.
  void _jumpToMessage(String messageId) {
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) {
      // Older than the loaded page. Saying so beats a tap that does nothing.
      _showError('That message is further back in the conversation');
      return;
    }
    // Approximate: rows carry separators too, so this lands near rather than
    // exactly on it. Better than not moving at all.
    _scrollController.animateTo(
      (index / _messages.length) * _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _toggleMute() async {
    final service = ref.read(chatServiceProvider);
    final wasMuted = _isMuted;

    // Optimistic, so the menu closes on a settled state; reverted on failure.
    setState(() => _isMuted = !wasMuted);

    final result = wasMuted
        ? await service.unmuteConversation(widget.conversation.id)
        : await service.muteConversation(widget.conversation.id);

    if (!mounted) return;
    if (!result.success) {
      setState(() => _isMuted = wasMuted);
      _showError(result.error ?? 'Could not change notifications');
    }
  }

  // ==================== Voice ====================

  VoiceRecording? _recorder;
  Timer? _recordingTimer;
  Duration _recordingElapsed = Duration.zero;

  /// Starts capture, or does nothing visible if the mic is refused.
  ///
  /// Injectable [make] so the flow is drivable in a test without a microphone
  /// or a permission prompt.
  Future<void> _startRecording({VoiceRecording Function()? make}) async {
    if (_recorder != null || _isSending) return;

    final rec = (make ?? DeviceVoiceRecording.new)();
    if (!await rec.start()) {
      await rec.dispose();
      if (mounted) _showError('Microphone permission is needed to record');
      return;
    }
    if (!mounted) {
      await rec.cancel();
      await rec.dispose();
      return;
    }

    setState(() {
      _recorder = rec;
      _recordingElapsed = Duration.zero;
    });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordingElapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _stopRecordingTimer() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
  }

  Future<void> _cancelRecording() async {
    final rec = _recorder;
    if (rec == null) return;
    await _stopRecordingTimer();
    setState(() => _recorder = null);
    await rec.cancel();
    await rec.dispose();
  }

  Future<void> _sendRecording() async {
    final rec = _recorder;
    if (rec == null) return;

    // Capture before clearing, so a failed send can restore the reply target —
    // same contract as _sendMessage and the attachment path.
    final sentReplyingTo = _replyingTo;
    final seconds = _recordingElapsed.inSeconds;

    await _stopRecordingTimer();
    final file = await rec.stop();
    await rec.dispose();
    if (!mounted) return;

    setState(() {
      _recorder = null;
      _recordingElapsed = Duration.zero;
    });

    // Nothing captured: a tap that started and stopped inside the same second
    // is a mis-tap, not a message.
    if (file == null) return;

    setState(() {
      _isSending = true;
      _replyingTo = null;
    });

    final error = await ref.read(conversationsProvider.notifier).sendVoiceMessage(
          widget.conversation.id,
          file,
          duration: seconds,
          replyToId: sentReplyingTo?.id,
        );

    if (!mounted) return;
    setState(() => _isSending = false);

    if (error == null) {
      await _refreshMessages();
      _scrollToBottom(animated: true);
    } else {
      setState(() => _replyingTo = sentReplyingTo);
      _showError(error);
    }
  }

  /// Opens the share sheet, then picks and sends whatever the user chose.
  ///
  /// Injectable [pick] so the flow can be driven in a test without a platform
  /// picker; production passes nothing and gets the real one.
  Future<void> _openAttachmentSheet({AttachmentPicker? pick}) async {
    if (_isSending) return;

    final kind = await showModalBottomSheet<ChatAttachmentKind>(
      context: context,
      builder: (sheetContext) => AttachmentModal(
        onPick: (k) => Navigator.pop(sheetContext, k),
      ),
    );
    if (kind == null || !mounted) return;

    final file = await (pick ?? pickAttachment)(kind);
    // Backing out of the picker is the common case, not an error.
    if (file == null || !mounted) return;

    // Capture the reply target before clearing it, so a failed send can put it
    // back — same contract as _sendMessage.
    final sentReplyingTo = _replyingTo;

    setState(() {
      _isSending = true;
      _replyingTo = null;
    });

    final error = await sendAttachment(
      kind: kind,
      notifier: ref.read(conversationsProvider.notifier),
      conversationId: widget.conversation.id,
      file: file,
      replyToId: sentReplyingTo?.id,
    );

    if (!mounted) return;
    setState(() => _isSending = false);

    if (error == null) {
      await _refreshMessages();
      _scrollToBottom(animated: true);
    } else {
      setState(() => _replyingTo = sentReplyingTo);
      _showError(error);
    }
  }

  // ==================== Message Actions ====================

  void _onMessageLongPress(Message message) {
    final currentUserId = ref.read(currentUserProvider).valueOrNull?.id ?? '';
    // Edit/delete are only offered on the current user's own, not-yet-deleted
    // messages.
    final isOwnMessage = message.isSentBy(currentUserId) && !message.isDeleted;

    showModalBottomSheet(
      context: context,
      builder: (context) => _MessageActionsSheet(
        isPinned: _pinned.any((p) => p.messageId == message.id),
        onTogglePin: () {
          Navigator.pop(context);
          if (_pinned.any((p) => p.messageId == message.id)) {
            _unpin(message.id);
          } else {
            _pin(message);
          }
        },
        onReply: () {
          Navigator.pop(context);
          setState(() => _replyingTo = message);
        },
        onReact: (emoji) {
          Navigator.pop(context);
          _addReaction(message.id, emoji);
        },
        onEdit: isOwnMessage
            ? () {
                Navigator.pop(context);
                _editMessage(message);
              }
            : null,
        onDelete: isOwnMessage
            ? () {
                Navigator.pop(context);
                _showDeleteOptions(message);
              }
            : null,
      ),
    );
  }

  Future<void> _addReaction(String messageId, String emoji) async {
    await ref
        .read(conversationsProvider.notifier)
        .addReaction(widget.conversation.id, messageId, emoji);
  }

  /// Prompts for new text via a dialog, then calls the real
  /// `PATCH /messages/:id` edit contract and replaces the message locally on
  /// success.
  Future<void> _editMessage(Message message) async {
    final controller = TextEditingController(text: message.content);

    final newText = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted) return;
    if (newText == null || newText.isEmpty || newText == message.content)
      return;

    final chatService = ref.read(chatServiceProvider);
    final result = await chatService.editMessage(message.id, newText);

    if (!mounted) return;

    if (result.success && result.data != null) {
      _replaceMessage(result.data!);
    } else {
      _showError(result.error ?? 'Failed to edit message');
    }
  }

  /// Shows the "Delete for me" / "Delete for everyone" sheet and dispatches
  /// the chosen scope to [_deleteMessage].
  void _showDeleteOptions(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete for me'),
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteMessage(message, scope: 'me');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text(
                'Delete for everyone',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                _deleteMessage(message, scope: 'everyone');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Calls the real `DELETE /messages/:id?scope=` contract and replaces the
  /// message locally with the returned tombstone on success.
  Future<void> _deleteMessage(Message message, {required String scope}) async {
    final chatService = ref.read(chatServiceProvider);
    final result = await chatService.deleteMessage(message.id, scope: scope);

    if (!mounted) return;

    if (result.success && result.data != null) {
      _replaceMessage(result.data!);
    } else {
      _showError(result.error ?? 'Failed to delete message');
    }
  }

  // ==================== Utilities ====================

  void _scrollToBottom({bool animated = false}) {
    if (_scrollController.hasClients) {
      final position = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          position,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(position);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ==================== Build Methods ====================

  @override
  Widget build(BuildContext context) {
    final conversationsState = ref.watch(conversationsProvider);
    final currentUserState = ref.watch(currentUserProvider);

    final currentConversation =
        conversationsState.maybeWhen(
          data: (conversations) => conversations
              .where((c) => c.id == widget.conversation.id)
              .firstOrNull,
          orElse: () => null,
        ) ??
        widget.conversation;

    final currentUserId = currentUserState.valueOrNull?.id ?? '';
    final isOtherUserTyping = _isOtherUserTypingFlame;

    // Check for new messages from WebSocket and add them to local list
    for (final msg in currentConversation.messages) {
      if (!_messages.any((m) => m.id == msg.id)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _messages = [..._messages, msg];
            });
            _scrollToBottom(animated: true);
          }
        });
        break; // Only add one at a time to avoid multiple setState calls
      }
    }

    return Scaffold(
      appBar: _buildAppBar(currentConversation, isOtherUserTyping),
      body: Column(
        children: [
          if (_pinned.isNotEmpty)
            _PinnedMessagesBar(
              pinned: _pinned,
              onTap: _jumpToMessage,
              onUnpin: _unpin,
            ),
          Expanded(child: _buildMessageList(currentUserId)),
          if (isOtherUserTyping)
            TypingIndicator(
              userPhotoUrl: currentConversation.otherUser.primaryPhoto,
            ),
          ChatInput(
            controller: _messageController,
            isSending: _isSending,
            replyingTo: _replyingTo,
            onSend: _sendMessage,
            onAttach: _openAttachmentSheet,
            onSticker: _openStickerPanel,
            onStartRecording: _startRecording,
            isRecording: _recorder != null,
            recordingElapsed: _recordingElapsed,
            onCancelRecording: _cancelRecording,
            onSendRecording: _sendRecording,
            onCancelReply: () => setState(() => _replyingTo = null),
            onChanged: _onMessageTextChanged,
          ),
        ],
      ),
    );
  }

  /// Whether the conversation's partner is online right now: prefers the
  /// live flame-socket `presence` state, falling back to the REST-seeded
  /// `is_online` snapshot if no presence event has been seen yet.
  bool _isPartnerOnline(Conversation conversation) {
    return _presence[conversation.otherUser.id] ??
        conversation.otherUser.isOnline;
  }

  PreferredSizeWidget _buildAppBar(Conversation conversation, bool isTyping) {
    return AppBar(
      titleSpacing: 0,
      title: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileDetailScreen(user: conversation.otherUser),
          ),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: conversation.otherUser.primaryPhoto
                      .toImageProvider(),
                ),
                if (_isPartnerOnline(conversation))
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppTheme.successColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.otherUser.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    isTyping
                        ? 'typing...'
                        : conversation.otherUser.lastActiveText,
                    style: TextStyle(
                      fontSize: 12,
                      color: isTyping
                          ? AppTheme.primaryColor
                          : Colors.grey[600],
                      fontWeight: isTyping
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        // The videocam button that used to sit here did nothing — there is no
        // calling feature anywhere in the app. A control that cannot work is
        // worse than a missing one.
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'mute':
                _toggleMute();
              case 'profile':
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileDetailScreen(user: conversation.otherUser),
                  ),
                );
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'mute',
              child: Row(
                children: [
                  Icon(_isMuted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined),
                  const SizedBox(width: 12),
                  Text(_isMuted ? 'Unmute notifications' : 'Mute notifications'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'profile',
              child: Row(
                children: [
                  Icon(Icons.person_outline),
                  SizedBox(width: 12),
                  Text('View profile'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessageList(String currentUserId) {
    if (_isLoadingMessages && _messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_messages.isEmpty) {
      return _buildEmptyChat();
    }

    // Rows, not raw messages: day separators are list items, which is what
    // makes "don't group a run across midnight" expressible at all.
    final rows = buildChatRows(_messages, now: DateTime.now());

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: rows.length + (_isLoadingMessages ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isLoadingMessages && index == 0) {
          return const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final row = rows[_isLoadingMessages ? index - 1 : index];

        return switch (row) {
          DateSeparatorRow(:final day) => _DateSeparatorChip(day: day),
          MessageRow(:final message, :final isFirstInGroup, :final isLastInGroup) =>
            MessageBubble(
              message: message,
              isMe: message.isSentBy(currentUserId),
              isFirstInGroup: isFirstInGroup,
              isLastInGroup: isLastInGroup,
              onLongPress: () => _onMessageLongPress(message),
            ),
        };
      },
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 50,
            backgroundImage: widget.conversation.otherUser.primaryPhoto
                .toImageProvider(),
          ),
          const SizedBox(height: 16),
          Text(
            'You matched with ${widget.conversation.otherUser.name}!',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to start the conversation',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

// ==================== Message Actions Sheet ====================

class _MessageActionsSheet extends StatelessWidget {
  final VoidCallback onReply;
  final void Function(String emoji) onReact;
  // Non-null only for the current user's own, not-yet-deleted messages —
  // their presence gates whether the Edit/Delete rows are shown at all.
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Pin state and toggle. Pinning is per-user, so this reflects whether the
  /// CALLER has pinned it, not whether anyone has.
  final bool isPinned;
  final VoidCallback onTogglePin;

  const _MessageActionsSheet({
    required this.onReply,
    required this.onReact,
    required this.isPinned,
    required this.onTogglePin,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick reactions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['❤️', '😂', '😮', '😢', '😡', '👍'].map((emoji) {
                return GestureDetector(
                  onTap: () => onReact(emoji),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
            title: Text(isPinned ? 'Unpin' : 'Pin'),
            onTap: onTogglePin,
          ),
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('Reply'),
            onTap: onReply,
          ),
          if (onEdit != null)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: onEdit,
            ),
          if (onDelete != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: onDelete,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// A day boundary in the conversation.
class _DateSeparatorChip extends StatelessWidget {
  final DateTime day;

  const _DateSeparatorChip({required this.day});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            chatDayLabel(day, DateTime.now()),
            style: theme.textTheme.labelSmall,
          ),
        ),
      ),
    );
  }
}

/// The caller's pinned messages, shown under the app bar.
///
/// Pinning is per-user — this is what YOU pinned, not what either participant
/// did. Shows the most recent, with a count when there is more than one, since
/// a bar tall enough for five pins is a bar that swallows the conversation.
class _PinnedMessagesBar extends StatelessWidget {
  final List<PinnedMessage> pinned;
  final void Function(String messageId) onTap;
  final void Function(String messageId) onUnpin;

  const _PinnedMessagesBar({
    required this.pinned,
    required this.onTap,
    required this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = pinned.last;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: () => onTap(latest.messageId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.push_pin, size: 16, color: AppTheme.primaryColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pinned.length == 1
                          ? 'Pinned message'
                          : 'Pinned · ${pinned.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      latest.content.isEmpty ? 'Attachment' : latest.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Unpin',
                onPressed: () => onUnpin(latest.messageId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
