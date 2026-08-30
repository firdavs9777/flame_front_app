import 'package:flame/core/navigation/app_routes.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/providers/realtime_provider.dart';
import 'package:flame/services/api_client.dart';
import 'package:flame/screens/chat/chat_attachments.dart' show AttachmentPicker;
import 'package:flame/screens/chat/conversation/handlers/composer_actions.dart';
import 'package:flame/screens/chat/conversation/handlers/thread_actions.dart';
import 'package:flame/screens/chat/dialogs/message_actions_sheet.dart';
import 'package:flame/screens/chat/header/chat_app_bar.dart';
import 'package:flame/screens/chat/header/pinned_messages_bar.dart';
import 'package:flame/screens/chat/message/messages_list.dart';
import 'package:flame/screens/chat/state/message_thread_provider.dart';
import 'package:flame/screens/chat/state/thread_presence_provider.dart';
import 'package:flame/screens/chat/voice_recording.dart';
import 'package:flame/screens/chat/widgets/chat_snackbar.dart';
import 'package:flame/screens/chat/widgets/widgets.dart';
import 'package:flame/services/chat_service.dart' show PinnedMessage;
import 'package:flame/widgets/report_block_menu.dart';

/// One open conversation.
///
/// An orchestrator: it owns the two controllers, the few flags that are genuinely
/// local to a screen (in-flight send, reply target, pin list, mute, recorder),
/// and nothing else. Messages belong to [messageThreadProvider], typing and
/// presence to [threadPresenceProvider], and every action to a free function
/// under `handlers/`.
///
/// What used to be here: 1437 lines and ~45 methods, including a loop inside
/// `build()` that scanned every message the conversation list held against every
/// message the screen held and admitted one per frame.
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
  Message? _replyingTo;

  /// The caller's pinned messages, loaded on open.
  List<PinnedMessage> _pinned = const [];

  /// Mirrors the conversation's is_muted so the menu reflects a toggle
  /// immediately rather than waiting for a list refetch.
  late bool _isMuted = widget.conversation.isMuted;

  VoiceRecording? _recorder;
  Timer? _recordingTimer;
  Duration _recordingElapsed = Duration.zero;

  String get _conversationId => widget.conversation.id;
  User get _otherUser => widget.conversation.otherUser;

  ThreadPresenceArgs get _presenceArgs => ThreadPresenceArgs(
        conversationId: _conversationId,
        otherUserId: _otherUser.id,
        seedOnline: _otherUser.isOnline,
      );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Post-frame because these read providers, and initState runs before the
    // element is ready to be listened to.
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    // Bring the app-level connection up on whatever token ApiClient holds now,
    // before subscribing to it. MainShell already does this on auth changes and
    // on resume, but neither fires when the socket simply died on a token that
    // has since been refreshed — and then a thread would subscribe to streams
    // nothing is feeding. `applySessionStatus` no-ops on an unchanged token, so
    // this is cheap when the connection is already healthy.
    //
    // `AuthStatus.authenticated` is passed literally rather than read from
    // authProvider: reaching an open conversation at all means the session is
    // live, and a refresh never touches authProvider anyway — which is the very
    // gap this call exists to close.
    final conn = ref.read(realtimeConnectionProvider);
    applySessionStatus(
      conn,
      AuthStatus.authenticated,
      () => ApiClient().accessToken,
    );

    final thread = ref.read(messageThreadProvider(_conversationId).notifier);
    thread.listen();
    await thread.load();
    if (!mounted) return;

    _scrollToBottom();
    await handleMarkRead(
      ref: ref,
      conversationId: _conversationId,
      otherUserId: _otherUser.id,
      connection: conn,
    );
    if (!mounted) return;

    final pinned = await handleLoadPinned(ref: ref, conversationId: _conversationId);
    if (mounted) setState(() => _pinned = pinned);
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    // Fire-and-forget: dispose() cannot await, and a dangling recorder would hold
    // the microphone after the screen is gone.
    _recorder?.cancel().then((_) => _recorder?.dispose()).catchError((_) {});
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  /// Older messages live at the top.
  ///
  /// A threshold rather than equality: this was `pixels == minScrollExtent`, and
  /// iOS bounce physics drives `pixels` negative on overscroll, so the equality
  /// held transiently at best and loading history often never fired at all.
  void _onScroll() {
    final p = _scrollController.position;
    if (p.pixels <= p.minScrollExtent + 80) {
      ref.read(messageThreadProvider(_conversationId).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = ref.watch(messageThreadProvider(_conversationId));
    final presence = ref.watch(threadPresenceProvider(_presenceArgs));
    final currentUserId = ref.watch(currentUserProvider).valueOrNull?.id ?? '';

    // No reconciliation here. The thread has one owner, so there is nothing to
    // merge and nothing to scan.

    return Scaffold(
      appBar: ChatAppBar(
        otherUser: _otherUser,
        presence: presence,
        isMuted: _isMuted,
        onToggleMute: _toggleMute,
        onOpenProfile: _openProfile,
        onReport: _reportPartner,
        onBlock: _blockPartner,
      ),
      body: Column(
        children: [
          if (_pinned.isNotEmpty)
            PinnedMessagesBar(
              pinned: _pinned,
              onTap: _jumpToMessage,
              onUnpin: _unpin,
            ),
          Expanded(
            child: ChatMessagesList(
              state: thread,
              currentUserId: currentUserId,
              otherUserName: _otherUser.name,
              otherUserPhoto: _otherUser.primaryPhoto,
              scrollController: _scrollController,
              onRetry: _retry,
              onMessageLongPress: _onMessageLongPress,
            ),
          ),
          if (presence.isOtherTyping)
            TypingIndicator(userPhotoUrl: _otherUser.primaryPhoto),
          ChatInput(
            controller: _messageController,
            isSending: _isSending,
            replyingTo: _replyingTo,
            onSend: _send,
            onAttach: _attach,
            onSticker: _sticker,
            onStartRecording: _startRecording,
            isRecording: _recorder != null,
            recordingElapsed: _recordingElapsed,
            onCancelRecording: _cancelRecording,
            onSendRecording: _sendRecording,
            onCancelReply: () => setState(() => _replyingTo = null),
            onChanged: (text) => ref
                .read(threadPresenceProvider(_presenceArgs).notifier)
                .onOutgoingText(text),
          ),
        ],
      ),
    );
  }

  // ==================== Delegates ====================
  //
  // Each is one line into a handler. The bodies live under handlers/ so they can
  // be tested without pumping this screen.

  void _setSending(bool v) {
    if (mounted) setState(() => _isSending = v);
  }

  void _setReplyingTo(Message? m) {
    if (mounted) setState(() => _replyingTo = m);
  }

  void _onSent() {
    ref.read(threadPresenceProvider(_presenceArgs).notifier).stopTypingNow();
    _scrollToBottom(animated: true);
  }

  void _retry() {
    final thread = ref.read(messageThreadProvider(_conversationId).notifier);
    // One control for both failures: an empty thread retries the initial load, a
    // populated one retries the older page that failed.
    if (ref.read(messageThreadProvider(_conversationId)).messages.isEmpty) {
      thread.load();
    } else {
      thread.loadMore();
    }
  }

  Future<void> _send() {
    if (_isSending) return Future.value();
    return handleSendText(
      context: context,
      ref: ref,
      conversationId: _conversationId,
      controller: _messageController,
      replyingTo: _replyingTo,
      setReplyingTo: _setReplyingTo,
      setSending: _setSending,
      onSent: _onSent,
    );
  }

  void _sticker() {
    if (_isSending) return;
    handleOpenStickerPanel(
      context: context,
      ref: ref,
      conversationId: _conversationId,
      replyingTo: _replyingTo,
      setReplyingTo: _setReplyingTo,
      setSending: _setSending,
      onSent: _onSent,
    );
  }

  Future<void> _attach({AttachmentPicker? pick}) {
    if (_isSending) return Future.value();
    return handleOpenAttachmentSheet(
      context: context,
      ref: ref,
      conversationId: _conversationId,
      replyingTo: _replyingTo,
      setReplyingTo: _setReplyingTo,
      setSending: _setSending,
      onSent: _onSent,
      pick: pick,
    );
  }

  Future<void> _toggleMute() async {
    final wasMuted = _isMuted;
    // Optimistic, so the menu closes on a settled state; the handler reports the
    // state to hold, which is the previous one if the server refused.
    setState(() => _isMuted = !wasMuted);
    final settled = await handleToggleMute(
      context: context,
      ref: ref,
      conversationId: _conversationId,
      wasMuted: wasMuted,
    );
    if (mounted) setState(() => _isMuted = settled);
  }

  void _openProfile() {
    Navigator.pushNamed(
      context,
      AppRoutes.profileDetail,
      arguments: ProfileDetailArgs(user: _otherUser),
    );
  }

  Future<void> _unpin(String messageId) async {
    final next = await handleUnpin(
      context: context,
      ref: ref,
      conversationId: _conversationId,
      messageId: messageId,
      current: _pinned,
    );
    if (mounted) setState(() => _pinned = next);
  }

  Future<void> _pin(Message message) async {
    final next = await handlePin(
      context: context,
      ref: ref,
      conversationId: _conversationId,
      messageId: message.id,
      current: _pinned,
    );
    if (mounted) setState(() => _pinned = next);
  }

  void _onMessageLongPress(Message message) {
    final currentUserId = ref.read(currentUserProvider).valueOrNull?.id ?? '';
    showMessageActions(
      context: context,
      ref: ref,
      conversationId: _conversationId,
      message: message,
      currentUserId: currentUserId,
      isPinned: _pinned.any((p) => p.messageId == message.id),
      onTogglePin: () => _pinned.any((p) => p.messageId == message.id)
          ? _unpin(message.id)
          : _pin(message),
      onReply: () => _setReplyingTo(message),
      onReport: () => showReportSheet(
        context,
        ref,
        userId: _otherUser.id,
        messageId: message.id,
      ),
    );
  }

  Future<void> _reportPartner() =>
      showReportSheet(context, ref, userId: _otherUser.id);

  /// Blocking ends the conversation, so the screen it happened on is about
  /// someone the user can no longer see. Leave it rather than sit on a dead
  /// thread.
  Future<void> _blockPartner() async {
    final blocked = await confirmAndBlock(
      context,
      ref,
      userId: _otherUser.id,
      userName: _otherUser.name,
    );
    if (blocked && mounted) Navigator.of(context).pop();
  }

  // ==================== Voice ====================

  Future<void> _startRecording({VoiceRecording Function()? make}) async {
    if (_recorder != null || _isSending) return;

    final rec = await handleStartRecording(context: context, make: make);
    if (rec == null || !mounted) return;

    setState(() {
      _recorder = rec;
      _recordingElapsed = Duration.zero;
    });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordingElapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _cancelRecording() async {
    final rec = _recorder;
    if (rec == null) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    setState(() => _recorder = null);
    await rec.cancel();
    await rec.dispose();
  }

  Future<void> _sendRecording() async {
    final rec = _recorder;
    if (rec == null) return;

    _recordingTimer?.cancel();
    _recordingTimer = null;
    final seconds = _recordingElapsed.inSeconds;
    setState(() {
      _recorder = null;
      _recordingElapsed = Duration.zero;
    });

    await handleSendRecording(
      context: context,
      ref: ref,
      conversationId: _conversationId,
      rec: rec,
      seconds: seconds,
      replyingTo: _replyingTo,
      setReplyingTo: _setReplyingTo,
      setSending: _setSending,
      onSent: _onSent,
    );
  }

  // ==================== Scrolling ====================
  //
  // These stay: they own the ScrollController.

  void _scrollToBottom({bool animated = false}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  /// Scrolls to a pinned message if it is loaded.
  void _jumpToMessage(String messageId) {
    final messages = ref.read(messageThreadProvider(_conversationId)).messages;
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index == -1) {
      // Older than the loaded page. Saying so beats a tap that does nothing.
      showChatSnackBar(context, message: context.l10n.chatMessageFurtherBack);
      return;
    }
    if (!_scrollController.hasClients) return;
    // Approximate: rows carry separators too, so this lands near rather than
    // exactly on it. Better than not moving at all.
    _scrollController.animateTo(
      (index / messages.length) * _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }
}
