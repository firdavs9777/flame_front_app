import 'package:flame/core/i18n/build_context_ext.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flame/models/models.dart';

/// Runs a search. A typedef rather than a service dependency so the screen is
/// drivable in a test without a network.
typedef MessageSearch = Future<List<Message>> Function(
  String query, {
  int limit,
  int offset,
});

/// Search across every conversation the user can still open.
///
/// Debounced at 500ms, following BananaTalk's
/// `pages/chat/search/chat_search_screen.dart`. Without it a five-letter word
/// is five requests against a route that allows twenty a minute.
///
/// Which conversations are searchable is decided by the backend, which scopes
/// the query through the same filter the Messages list uses — a blocked or
/// unmatched partner's messages never come back. That rule is deliberately not
/// duplicated here.
class ChatSearchScreen extends StatefulWidget {
  final MessageSearch search;

  const ChatSearchScreen({super.key, required this.search});

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Message> _results = [];
  bool _isLoading = false;
  /// See the note in ArchivedConversationsScreen: a flag, resolved at render.
  bool _failed = false;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();

    final query = raw.trim();
    if (query.isEmpty) {
      // Not a search. Clearing the box clears the screen; the backend 422s an
      // empty q, so spending the call to find that out is pure waste.
      setState(() {
        _results = [];
        _failed = false;
        _isLoading = false;
        _searched = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 500), () => _run(query));
  }

  Future<void> _run(String query) async {
    setState(() {
      _isLoading = true;
      _failed = false;
    });

    try {
      final results = await widget.search(query);
      // The user can leave while this is in flight; setState after disposal
      // throws.
      if (!mounted) return;
      setState(() {
        _results = results;
        _isLoading = false;
        _searched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _isLoading = false;
        _searched = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.l10n.searchMessages,
            border: InputBorder.none,
          ),
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(context.l10n.searchFailed, textAlign: TextAlign.center),
        ),
      );
    }
    if (_searched && _results.isEmpty) {
      return Center(child: Text(context.l10n.searchNoResults));
    }

    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final m = _results[i];
        return ListTile(
          title: Text(m.content, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(m.timeText),
        );
      },
    );
  }
}
