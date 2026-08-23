import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flutter/material.dart';
import 'package:flame/models/models.dart';

/// Loads the archived conversations.
typedef ArchivedLoader = Future<List<Conversation>> Function();

/// Unarchives one. Returns null on success, or a message to show.
typedef ArchivedAction = Future<String?> Function(String conversationId);

/// The conversations the user has filed away.
///
/// This screen is not optional. `listConversations` hides archived
/// conversations from the default list, so without somewhere to see them
/// archiving would make a conversation unreachable — the messages still there,
/// the user unable to get to them.
///
/// Both callbacks are injected rather than read from providers so the screen is
/// drivable in a test without a network.
class ArchivedConversationsScreen extends StatefulWidget {
  final ArchivedLoader load;
  final ArchivedAction unarchive;

  const ArchivedConversationsScreen({
    super.key,
    required this.load,
    required this.unarchive,
  });

  @override
  State<ArchivedConversationsScreen> createState() =>
      _ArchivedConversationsScreenState();
}

class _ArchivedConversationsScreenState
    extends State<ArchivedConversationsScreen> {
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  /// A flag, not a message: the copy is resolved at render time so it follows
  /// the app's locale instead of freezing whichever one was active on failure.
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final conversations = await widget.load();
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _failed = false;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _unarchive(Conversation c) async {
    final error = await widget.unarchive(c.id);
    if (!mounted) return;

    if (error != null) {
      // Leave the row where it is. Removing one whose server-side state did
      // not change would show the user something untrue.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _conversations.removeWhere((x) => x.id == c.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.archivedTitle)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.l10n.archivedLoadFailed, textAlign: TextAlign.center),
        ),
      );
    }
    if (_conversations.isEmpty) {
      return Center(child: Text(context.l10n.archivedEmpty));
    }

    return ListView.builder(
      itemCount: _conversations.length,
      itemBuilder: (context, i) {
        final c = _conversations[i];
        return ListTile(
          title: Text(c.otherUser.name),
          subtitle: Text(
            c.lastMessagePreview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.unarchive_outlined),
            tooltip: context.l10n.unarchive,
            onPressed: () => _unarchive(c),
          ),
        );
      },
    );
  }
}
