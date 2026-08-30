import 'package:flutter/material.dart';

import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flame/l10n/gen/app_localizations.dart';

/// One sticker category: a stable id, a localised label, and its emoji.
///
/// The id is what the panel tracks the selection by, and it is never shown.
/// The two used to be the same string — a `Map<String, List<String>>` keyed by
/// 'Smileys' — so the tab bar read English in every locale.
class StickerCategory {
  const StickerCategory(this.id, this._label, this.emoji);

  final String id;
  final String Function(AppLocalizations) _label;
  final List<String> emoji;

  String label(AppLocalizations l10n) => _label(l10n);
}

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
const List<StickerCategory> stickerCategories = [
  StickerCategory('smileys', _smileys, [
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣',
    '😊', '😇', '🙂', '🙃', '😉', '😌', '😍', '🥰',
    '😘', '😗', '😙', '😚', '😋', '😛', '😝', '😜',
  ]),
  StickerCategory('feelings', _feelings, [
    '🤪', '🤨', '🧐', '🤓', '😎', '🥸', '🤩', '🥳',
    '😏', '😒', '😞', '😔', '😟', '😕', '🙁', '☹️',
    '😤', '😠', '😡', '🥺', '😢', '😭', '😱', '😳',
  ]),
  StickerCategory('gestures', _gestures, [
    '👍', '👎', '👌', '✌️', '🤞', '🤟', '🤘', '🤙',
    '👈', '👉', '👆', '👇', '☝️', '👋', '🤚', '🖐️',
    '✋', '🖖', '👏', '🙌', '🤝', '🙏', '✍️', '💪',
  ]),
  StickerCategory('hearts', _hearts, [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
    '🤎', '💔', '❣️', '💕', '💞', '💓', '💗', '💖',
    '💘', '💝', '💟', '♥️', '💌', '💋', '💍', '🌹',
  ]),
];

String _smileys(AppLocalizations l) => l.stickerSmileys;
String _feelings(AppLocalizations l) => l.stickerFeelings;
String _gestures(AppLocalizations l) => l.stickerGestures;
String _hearts(AppLocalizations l) => l.stickerHearts;

/// A sticker picker for the chat composer.
class StickerPanel extends StatefulWidget {
  final ValueChanged<String> onPick;

  const StickerPanel({super.key, required this.onPick});

  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  late String _category = stickerCategories.first.id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emoji =
        stickerCategories.firstWhere((c) => c.id == _category).emoji;

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
                children: stickerCategories.map((category) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: ChoiceChip(
                      label: Text(category.label(context.l10n)),
                      selected: category.id == _category,
                      onSelected: (_) =>
                          setState(() => _category = category.id),
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
