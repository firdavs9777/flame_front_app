import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/config/env.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/screens/profile/profile_detail_screen.dart';
import 'package:flame/widgets/smart_image.dart';
import 'package:flame/screens/chat/widgets/widgets.dart';
import '../../realtime/widgets/connection_banner.dart';

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

  @override
  void initState() {
    super.initState();
    _loadInitialMessages();
    _scrollController.addListener(_onScroll);
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==================== Data Loading ====================

  void _onScroll() {
    if (_scrollController.position.pixels == _scrollController.position.minScrollExtent) {
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
      final oldExtent = hasScrollClient ? _scrollController.position.maxScrollExtent : 0.0;
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
        .where((m) => m.status != MessageStatus.read && !m.isSentBy(currentUserId))
        .map((m) => m.id)
        .toList();

    if (unreadIds.isNotEmpty) {
      ref.read(conversationsProvider.notifier).markAsRead(widget.conversation.id);
    }
  }

  // ==================== Messaging ====================

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    // Capture the content and reply target before clearing the input, so
    // they can be restored if the send fails.
    final sentReplyingTo = _replyingTo;
    final replyToId = sentReplyingTo?.id;

    setState(() {
      _isSending = true;
      _replyingTo = null;
    });
    _messageController.clear();

    final error = await ref.read(conversationsProvider.notifier).sendMessage(
      widget.conversation.id,
      content,
      replyToId: replyToId,
    );

    if (mounted) {
      setState(() => _isSending = false);

      if (error == null) {
        await _refreshMessages();
        _scrollToBottom(animated: true);
      } else {
        // Restore the user's input and reply target so nothing is lost.
        setState(() {
          _messageController.text = content;
          _messageController.selection = TextSelection.collapsed(offset: content.length);
          _replyingTo = sentReplyingTo;
        });
        _showError(error);
      }
    }
  }

  // ==================== Message Actions ====================

  void _onMessageLongPress(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _MessageActionsSheet(
        onReply: () {
          Navigator.pop(context);
          setState(() => _replyingTo = message);
        },
        onReact: (emoji) {
          Navigator.pop(context);
          _addReaction(message.id, emoji);
        },
      ),
    );
  }

  Future<void> _addReaction(String messageId, String emoji) async {
    await ref.read(conversationsProvider.notifier).addReaction(
      widget.conversation.id,
      messageId,
      emoji,
    );
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
    final typingUsers = ref.watch(typingUsersProvider);

    final currentConversation = conversationsState.maybeWhen(
      data: (conversations) => conversations.where(
        (c) => c.id == widget.conversation.id,
      ).firstOrNull,
      orElse: () => null,
    ) ?? widget.conversation;

    final currentUserId = currentUserState.valueOrNull?.id ?? '';
    final isOtherUserTyping = typingUsers[widget.conversation.id] != null;

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
          const ConnectionBanner(),
          Expanded(child: _buildMessageList(currentUserId)),
          if (isOtherUserTyping)
            TypingIndicator(userPhotoUrl: currentConversation.otherUser.primaryPhoto),
          ChatInput(
            controller: _messageController,
            isSending: _isSending,
            replyingTo: _replyingTo,
            onSend: _sendMessage,
            onCancelReply: () => setState(() => _replyingTo = null),
          ),
        ],
      ),
    );
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
                  backgroundImage: conversation.otherUser.primaryPhoto.toImageProvider(),
                ),
                if (conversation.otherUser.isOnline)
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
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    isTyping ? 'typing...' : conversation.otherUser.lastActiveText,
                    style: TextStyle(
                      fontSize: 12,
                      color: isTyping ? AppTheme.primaryColor : Colors.grey[600],
                      fontWeight: isTyping ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () {}),
        IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
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

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length + (_isLoadingMessages ? 1 : 0),
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

        final messageIndex = _isLoadingMessages ? index - 1 : index;
        final message = _messages[messageIndex];
        final isMe = message.isSentBy(currentUserId);

        return MessageBubble(
          message: message,
          isMe: isMe,
          onLongPress: () => _onMessageLongPress(message),
        );
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
            backgroundImage: widget.conversation.otherUser.primaryPhoto.toImageProvider(),
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

  const _MessageActionsSheet({
    required this.onReply,
    required this.onReact,
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
            leading: const Icon(Icons.reply),
            title: const Text('Reply'),
            onTap: onReply,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
