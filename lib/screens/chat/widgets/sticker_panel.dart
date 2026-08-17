import 'package:flutter/material.dart';

/// The stickers, by category.
///
/// Unicode emoji, not hosted artwork — the model BananaTalk uses in
/// `pages/chat/panels/chat_sticker_panel.dart`. Flame's inherited
/// `sticker_picker.dart` was written against a pack catalog with per-user
/// ownership and remote assets, which has never existed in either backend and
/// is why its five endpoints 404.
///
/// Being plain characters, they need no download, no cache, no licensing, and
/// they render at any size on every platform.
const Map<String, List<String>> stickerCategories = {
  'Smileys': [
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣',
    '😊', '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰',
    '😘', '😗', '😙', '😚', '😋', '😛', '😝', '😜',
  ],
  'Feelings': [
    '🤪', '🤨', '🧐', '🤓', '😎', '🥸', '🤩', '🥳',
    '😏', '😒', '😞', '😔', '😟', '😕', '🙁', '☹️',
    '😤', '😠', '😡', '🥺', '😢', '😭', '😱', '😳',
  ],
  'Gestures': [
    '👍', '👎', '👌', '✌️', '🤞', '🤟', '🤘', '🤙',
    '👈', '👉', '👆', '👇', '☝️', '👋', '🤚', '🖐️',
    '✋', '🖖', '👏', '🙌', '🤝', '🙏', '✍️', '💪',
  ],
  'Hearts': [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
    '🤎', '💔', '❣️', '💕', '💞', '💓', '💗', '💖',
    '💘', '💝', '💟', '♥️', '💌', '💋', '💍', '🌹',
  ],
};

/// A sticker picker for the chat composer.
class StickerPanel extends StatefulWidget {
  final ValueChanged<String> onPick;

  const StickerPanel({super.key, required this.onPick});

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  late String _category = stickerCategories.keys.first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emoji = stickerCategories[_category]!;

    return Container(
      height: 280,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: stickerCategories.keys.map((name) {
                  final selected = name == _category;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: ChoiceChip(
                      label: Text(name),
                      selected: selected,
                      onSelected: (_) => setState(() => _category = name),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                ),
                itemCount: emoji.length,
                itemBuilder: (context, i) => InkWell(
                  onTap: () => widget.onPick(emoji[i]),
                  child: Center(
                    child: Text(emoji[i], style: const TextStyle(fontSize: 26)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
