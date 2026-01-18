import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/screens/profile/profile_detail_screen.dart';
import 'package:flame/widgets/smart_image.dart';
import 'package:flame/screens/chat/widgets/widgets.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final Conversation conversation;

  const ChatScreen({super.key, required this.conversation});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  bool _isSending = false;
  bool _isLoadingMessages = false;
  bool _hasMoreMessages = true;
  List<Message> _messages = [];

  Timer? _typingTimer;
  bool _isTyping = false;
  Message? _replyingTo;

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
    if (_isTyping) {
      ref.read(conversationsProvider.notifier).sendStopTyping(widget.conversation.id);
    }
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
          _messages = result.data!.messages;
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

  void _onTextChanged(String text) {
    if (text.isNotEmpty) {
      if (!_isTyping) {
        _isTyping = true;
        ref.read(conversationsProvider.notifier).sendTyping(widget.conversation.id);
      }

      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _isTyping = false;
        ref.read(conversationsProvider.notifier).sendStopTyping(widget.conversation.id);
      });
    } else {
      _typingTimer?.cancel();
      if (_isTyping) {
        _isTyping = false;
        ref.read(conversationsProvider.notifier).sendStopTyping(widget.conversation.id);
      }
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _messageController.clear();

    _typingTimer?.cancel();
    if (_isTyping) {
      _isTyping = false;
      ref.read(conversationsProvider.notifier).sendStopTyping(widget.conversation.id);
    }

    final replyToId = _replyingTo?.id;
    setState(() => _replyingTo = null);

    final success = await ref.read(conversationsProvider.notifier).sendMessage(
      widget.conversation.id,
      content,
      replyToId: replyToId,
    );

    if (mounted) {
      setState(() => _isSending = false);

      if (success) {
        await _refreshMessages();
        _scrollToBottom(animated: true);
      } else {
        _showError('Failed to send message');
      }
    }
  }

  // ==================== Attachments ====================

  void _showAttachmentModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => AttachmentModal(
        onImageTap: () {
          Navigator.pop(context);
          _pickImage(ImageSource.gallery);
        },
        onCameraTap: () {
          Navigator.pop(context);
          _pickImage(ImageSource.camera);
        },
        onVideoTap: () {
          Navigator.pop(context);
          _pickVideo();
        },
        onVoiceTap: () {
          Navigator.pop(context);
          _showVoiceRecordingInfo();
        },
        onGifTap: () {
          Navigator.pop(context);
          _showComingSoon('GIF');
        },
        onStickerTap: () {
          Navigator.pop(context);
          _showComingSoon('Stickers');
        },
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() => _isSending = true);

      final replyToId = _replyingTo?.id;
      setState(() => _replyingTo = null);

      final success = await ref.read(conversationsProvider.notifier).sendImageMessage(
        widget.conversation.id,
        File(image.path),
        replyToId: replyToId,
      );

      if (mounted) {
        setState(() => _isSending = false);

        if (success) {
          await _refreshMessages();
          _scrollToBottom(animated: true);
        } else {
          _showError('Failed to send image');
        }
      }
    } catch (e) {
      _showError('Failed to pick image');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video == null) return;

      setState(() => _isSending = true);

      // TODO: Implement video sending when backend supports it
      _showComingSoon('Video messages');
      setState(() => _isSending = false);
    } catch (e) {
      _showError('Failed to pick video');
    }
  }

  void _showVoiceRecordingInfo() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Hold the mic button to record a voice message'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature coming soon!'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ==================== Message Actions ====================

  void _onMessageLongPress(Message message) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _MessageActionsSheet(
        message: message,
        isMe: message.isSentBy(_getCurrentUserId()),
        onReply: () {
          Navigator.pop(context);
          setState(() => _replyingTo = message);
        },
        onReact: (emoji) {
          Navigator.pop(context);
          _addReaction(message.id, emoji);
        },
        onEdit: message.type == MessageType.text ? () {
          Navigator.pop(context);
          _showEditDialog(message);
        } : null,
        onDelete: () {
          Navigator.pop(context);
          _showDeleteConfirmation(message);
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

  void _showEditDialog(Message message) {
    final editController = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: editController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Edit your message...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final newContent = editController.text.trim();
              if (newContent.isNotEmpty && newContent != message.content) {
                await ref.read(conversationsProvider.notifier).editMessage(
                  widget.conversation.id,
                  message.id,
                  newContent,
                );
                await _refreshMessages();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(Message message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(conversationsProvider.notifier).deleteMessage(
                widget.conversation.id,
                message.id,
                forEveryone: true,
              );
              await _refreshMessages();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ==================== Utilities ====================

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

    // Update local messages when conversation messages change
    if (currentConversation.messages.length > _messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _messages = currentConversation.messages);
          _scrollToBottom(animated: true);
        }
      });
    }

    return Scaffold(
      appBar: _buildAppBar(currentConversation, isOtherUserTyping),
      body: Column(
        children: [
          Expanded(child: _buildMessageList(currentUserId)),
          if (isOtherUserTyping)
            TypingIndicator(userPhotoUrl: currentConversation.otherUser.primaryPhoto),
          ChatInput(
            controller: _messageController,
            isSending: _isSending,
            replyingTo: _replyingTo,
            onSend: _sendMessage,
            onCancelReply: () => setState(() => _replyingTo = null),
            onAttachmentTap: _showAttachmentModal,
            onStickerTap: () {}, // TODO: Implement
            onTextChanged: _onTextChanged,
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
  final Message message;
  final bool isMe;
  final VoidCallback onReply;
  final void Function(String emoji) onReact;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  const _MessageActionsSheet({
    required this.message,
    required this.isMe,
    required this.onReply,
    required this.onReact,
    this.onEdit,
    required this.onDelete,
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
          if (isMe && onEdit != null)
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit'),
              onTap: onEdit,
            ),
          if (isMe)
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: onDelete,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
