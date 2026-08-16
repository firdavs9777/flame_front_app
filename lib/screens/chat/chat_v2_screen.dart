import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../realtime/messages_provider.dart';
import '../../realtime/typing_provider.dart';
import '../../realtime/providers.dart';
import '../../realtime/constants.dart';
import '../../realtime/widgets/gif_picker.dart';
import '../../realtime/widgets/sticker_picker.dart';

class ChatV2Screen extends ConsumerStatefulWidget {
  final String conversationId;
  final String peerName;
  final String? peerAvatarUrl;

  const ChatV2Screen({
    super.key,
    required this.conversationId,
    required this.peerName,
    this.peerAvatarUrl,
  });

  @override
  ConsumerState<ChatV2Screen> createState() => _ChatV2ScreenState();
}

class _ChatV2ScreenState extends ConsumerState<ChatV2Screen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  String? _openPicker; // null | 'gif' | 'sticker'

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    await ref.read(outboxProvider.notifier).sendText(
          conversationId: widget.conversationId,
          content: text,
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String _) {
    final socket = ref.read(socketClientProvider);
    socket.emit(
        RtEvents.typingStart, {'conversation_id': widget.conversationId});
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(messagesProvider(widget.conversationId));
    final peerTyping = ref.watch(typingProvider(widget.conversationId));
    final outbox = ref
        .watch(outboxProvider)
        .where((e) => e.conversationId == widget.conversationId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: widget.peerAvatarUrl != null
                  ? NetworkImage(widget.peerAvatarUrl!)
                  : null,
              child: widget.peerAvatarUrl == null
                  ? Text(widget.peerName.isNotEmpty ? widget.peerName[0] : '?')
                  : null,
            ),
            const SizedBox(width: 12),
            Text(widget.peerName),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: messages.length + outbox.length,
              itemBuilder: (ctx, i) {
                if (i < messages.length) {
                  final m = messages[i];
                  return _MessageRow(text: m.content, isMine: false);
                }
                final p = outbox[i - messages.length];
                return _MessageRow(
                    text: p.content, isMine: true, pending: true);
              },
            ),
          ),
          if (peerTyping)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('typing…',
                    style: TextStyle(
                        color: Colors.grey, fontStyle: FontStyle.italic)),
              ),
            ),
          if (_openPicker == 'gif')
            GifPicker(
              onPick: (url, w, h) {
                ref.read(outboxProvider.notifier).sendGif(
                      conversationId: widget.conversationId,
                      gifUrl: url,
                      width: w,
                      height: h,
                    );
                setState(() => _openPicker = null);
              },
            ),
          if (_openPicker == 'sticker')
            StickerPicker(
              onPick: (id, url) {
                ref.read(outboxProvider.notifier).sendSticker(
                      conversationId: widget.conversationId,
                      stickerId: id,
                      stickerUrl: url,
                    );
                setState(() => _openPicker = null);
              },
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.gif_box_outlined),
                    onPressed: () => setState(() =>
                        _openPicker = _openPicker == 'gif' ? null : 'gif'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    onPressed: () => setState(() => _openPicker =
                        _openPicker == 'sticker' ? null : 'sticker'),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      onChanged: _onTextChanged,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final String text;
  final bool isMine;
  final bool pending;
  const _MessageRow(
      {required this.text, required this.isMine, this.pending = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isMine ? Colors.blue.shade100 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(text)),
              if (pending) ...[
                const SizedBox(width: 6),
                const Icon(Icons.access_time, size: 12, color: Colors.grey),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
