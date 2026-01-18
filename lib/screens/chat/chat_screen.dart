import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/screens/profile/profile_detail_screen.dart';
import 'package:flame/widgets/smart_image.dart';

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
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _loadInitialMessages();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    // Send stop typing when leaving
    ref.read(conversationsProvider.notifier).sendStopTyping(widget.conversation.id);
    super.dispose();
  }

  void _onScroll() {
    // Load more messages when scrolling to top
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
          _messages = result.data!.messages;
          _hasMoreMessages = result.data!.hasMore;
        }
      });

      // Scroll to bottom after messages load
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });

      // Mark messages as read
      _markMessagesAsRead();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMessages || !_hasMoreMessages || _messages.isEmpty) return;

    setState(() => _isLoadingMessages = true);

    final chatService = ref.read(chatServiceProvider);
    final result = await chatService.getMessages(
      widget.conversation.id,
      before: _messages.first.id,
    );

    if (mounted) {
      setState(() {
        _isLoadingMessages = false;
        if (result.success && result.data != null) {
          _messages = [...result.data!.messages, ..._messages];
          _hasMoreMessages = result.data!.hasMore;
        }
      });
    }
  }

  void _markMessagesAsRead() {
    final unreadIds = _messages
        .where((m) => m.status != MessageStatus.read && !m.isSentBy(_getCurrentUserId()))
        .map((m) => m.id)
        .toList();

    if (unreadIds.isNotEmpty) {
      ref.read(conversationsProvider.notifier).markAsRead(widget.conversation.id);
    }
  }

  String _getCurrentUserId() {
    return ref.read(currentUserProvider).valueOrNull?.id ?? '';
  }

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

  void _onTextChanged(String text) {
    if (text.isNotEmpty) {
      // Send typing indicator
      ref.read(conversationsProvider.notifier).sendTyping(widget.conversation.id);

      // Reset typing timer
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        ref.read(conversationsProvider.notifier).sendStopTyping(widget.conversation.id);
      });
    } else {
      // Stop typing
      _typingTimer?.cancel();
      ref.read(conversationsProvider.notifier).sendStopTyping(widget.conversation.id);
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    // Stop typing indicator
    _typingTimer?.cancel();
    ref.read(conversationsProvider.notifier).sendStopTyping(widget.conversation.id);

    final success = await ref.read(conversationsProvider.notifier).sendMessage(
      widget.conversation.id,
      content,
    );

    if (mounted) {
      setState(() => _isSending = false);

      if (success) {
        // Reload messages to get the sent message
        await _refreshMessages();
        _scrollToBottom(animated: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _refreshMessages() async {
    final chatService = ref.read(chatServiceProvider);
    final result = await chatService.getMessages(widget.conversation.id);

    if (mounted && result.success && result.data != null) {
      setState(() {
        _messages = result.data!.messages;
        _hasMoreMessages = result.data!.hasMore;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversationsState = ref.watch(conversationsProvider);
    final currentUserState = ref.watch(currentUserProvider);
    final typingUsers = ref.watch(typingUsersProvider);

    // Find the current conversation from state for real-time updates
    final currentConversation = conversationsState.maybeWhen(
      data: (conversations) => conversations.where(
        (c) => c.id == widget.conversation.id,
      ).firstOrNull,
      orElse: () => null,
    ) ?? widget.conversation;

    final currentUser = currentUserState.valueOrNull;
    final currentUserId = currentUser?.id ?? '';

    // Check if other user is typing
    final isOtherUserTyping = typingUsers[widget.conversation.id] != null;

    // Update local messages when conversation messages change
    if (currentConversation.messages.length > _messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _messages = currentConversation.messages;
          });
          _scrollToBottom(animated: true);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileDetailScreen(
                  user: currentConversation.otherUser,
                ),
              ),
            );
          },
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: currentConversation.otherUser.primaryPhoto.toImageProvider(),
                  ),
                  if (currentConversation.otherUser.isOnline)
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
                      currentConversation.otherUser.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      isOtherUserTyping
                          ? 'typing...'
                          : currentConversation.otherUser.lastActiveText,
                      style: TextStyle(
                        fontSize: 12,
                        color: isOtherUserTyping ? AppTheme.primaryColor : Colors.grey[600],
                        fontWeight: isOtherUserTyping ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoadingMessages && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _buildEmptyChat()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length + (_isLoadingMessages ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Show loading indicator at top when loading more
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
                          return _MessageBubble(
                            message: message,
                            isMe: isMe,
                          );
                        },
                      ),
          ),
          // Typing indicator
          if (isOtherUserTyping)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundImage: currentConversation.otherUser.primaryPhoto.toImageProvider(),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TypingDot(delay: 0),
                        const SizedBox(width: 4),
                        _TypingDot(delay: 150),
                        const SizedBox(width: 4),
                        _TypingDot(delay: 300),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          _buildMessageInput(),
        ],
      ),
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
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
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

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
              onPressed: () {},
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                textCapitalization: TextCapitalization.sentences,
                onChanged: _onTextChanged,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isSending ? null : _sendMessage,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isSending ? Colors.grey : AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.send,
                        color: Colors.white,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;

  const _MessageBubble({
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? AppTheme.primaryColor : Colors.grey[200],
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 20),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (message.type == MessageType.image && message.content.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      message.content,
                      width: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                    ),
                  )
                else
                  Text(
                    message.content,
                    style: TextStyle(
                      color: isMe ? Colors.white : Colors.black87,
                      fontSize: 15,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.timeText,
                      style: TextStyle(
                        color: isMe ? Colors.white70 : Colors.grey[500],
                        fontSize: 11,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.status == MessageStatus.read
                            ? Icons.done_all
                            : message.status == MessageStatus.delivered
                                ? Icons.done_all
                                : Icons.done,
                        size: 14,
                        color: message.status == MessageStatus.read
                            ? Colors.blue[200]
                            : Colors.white70,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Animated typing dot
class _TypingDot extends StatefulWidget {
  final int delay;

  const _TypingDot({required this.delay});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) {
        _controller.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.grey[500]!.withValues(alpha: 0.5 + _animation.value * 0.5),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
