import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/core/navigation/app_routes.dart';
import 'package:flame/models/conversation.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/screens/chat/conversation/chat_screen.dart';

/// Turns a [ChatRouteArgs] into a [ChatScreen].
///
/// The conversation-list path already holds its conversation and goes straight
/// through, paying nothing. Only the id path — a push-notification tap — has to
/// resolve, and it tries the loaded list first because that covers the common
/// case of the app already being open.
///
/// The fetch matters for the uncommon one: the list is paginated, so a
/// notification about an older conversation is not in memory and looking only
/// there would leave the tap doing nothing at all.
class ChatRouteResolver extends ConsumerStatefulWidget {
  const ChatRouteResolver({super.key, required this.args});

  final ChatRouteArgs args;

  @override
  ConsumerState<ChatRouteResolver> createState() => _ChatRouteResolverState();
}

class _ChatRouteResolverState extends ConsumerState<ChatRouteResolver> {
  Conversation? _conversation;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _conversation = widget.args.conversation;
    if (_conversation == null) {
      // After the first frame: this reads a provider and may setState, neither
      // of which belongs in initState.
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
    }
  }

  Future<void> _resolve() async {
    final id = widget.args.id;
    if (id == null) return;

    final loaded = ref.read(conversationsProvider).valueOrNull ?? const [];
    final fromList = loaded.where((c) => c.id == id).firstOrNull;
    if (fromList != null) {
      setState(() => _conversation = fromList);
      return;
    }

    setState(() => _failed = false);
    final result = await ref.read(chatServiceProvider).getConversation(id);
    if (!mounted) return;
    setState(() {
      _conversation = result.data;
      _failed = !result.success || result.data == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final conversation = _conversation;
    if (conversation != null) return ChatScreen(conversation: conversation);

    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: _failed
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.l10n.chatLoadFailed,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _resolve,
                      child: Text(context.l10n.retry),
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
