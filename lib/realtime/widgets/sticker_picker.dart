import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/chat_service.dart';

/// Sticker picker with a horizontal pack-tab strip and a grid of stickers.
/// Backed by `ChatService.getStickerPacks()` + `getStickerPackDetails(packId)`.
/// On tap, invokes [onPick] with the sticker id and image URL — the URL must
/// satisfy the backend's CDN whitelist (`my-projects-media.sfo3.cdn...`).
class StickerPicker extends ConsumerStatefulWidget {
  final void Function(String stickerId, String stickerUrl) onPick;
  const StickerPicker({super.key, required this.onPick});

  @override
  ConsumerState<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends ConsumerState<StickerPicker> {
  final _chat = ChatService();

  bool _loadingPacks = true;
  bool _loadingStickers = false;
  String? _error;
  List<StickerPack> _packs = [];
  int _activeIndex = 0;
  final Map<String, List<Sticker>> _packStickers = {};

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    final result = await _chat.getStickerPacks();
    if (!mounted) return;
    if (result.success) {
      _packs = result.data ?? [];
      _loadingPacks = false;
      setState(() {});
      if (_packs.isNotEmpty) {
        await _loadStickersFor(_packs.first.id);
      }
    } else {
      setState(() {
        _loadingPacks = false;
        _error = result.error ?? 'Failed to load sticker packs';
      });
    }
  }

  Future<void> _loadStickersFor(String packId) async {
    if (_packStickers.containsKey(packId)) return;
    setState(() => _loadingStickers = true);
    final result = await _chat.getStickerPackDetails(packId);
    if (!mounted) return;
    if (result.success && result.data != null) {
      _packStickers[packId] = result.data!.stickers;
    } else {
      _packStickers[packId] = const [];
    }
    setState(() => _loadingStickers = false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: _loadingPacks
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.grey)),
                )
              : (_packs.isEmpty)
                  ? const Center(
                      child: Text(
                        'No sticker packs available',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : Column(
                      children: [
                        SizedBox(
                          height: 56,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            itemCount: _packs.length,
                            separatorBuilder: (_, i) =>
                                const SizedBox(width: 8),
                            itemBuilder: (ctx, i) {
                              final p = _packs[i];
                              final selected = i == _activeIndex;
                              return GestureDetector(
                                onTap: () async {
                                  setState(() => _activeIndex = i);
                                  await _loadStickersFor(p.id);
                                },
                                child: Container(
                                  width: 48,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: selected
                                          ? Colors.blue
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: p.thumbnailUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: p.thumbnailUrl,
                                          fit: BoxFit.contain,
                                          placeholder: (c, _) => Container(
                                              color: Colors.grey.shade200),
                                          errorWidget: (c, _, e) =>
                                              const Icon(Icons.image,
                                                  size: 24),
                                        )
                                      : const Icon(Icons.emoji_emotions,
                                          size: 24),
                                ),
                              );
                            },
                          ),
                        ),
                        if (_loadingStickers)
                          const LinearProgressIndicator(minHeight: 2),
                        Expanded(child: _buildGrid()),
                      ],
                    ),
    );
  }

  Widget _buildGrid() {
    final packId = _packs[_activeIndex].id;
    final stickers = _packStickers[packId] ?? const <Sticker>[];
    if (stickers.isEmpty && !_loadingStickers) {
      return const Center(
        child: Text('No stickers in this pack',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: stickers.length,
      itemBuilder: (ctx, i) {
        final s = stickers[i];
        return GestureDetector(
          onTap: () => widget.onPick(s.id, s.imageUrl),
          child: s.imageUrl.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: s.imageUrl,
                  fit: BoxFit.contain,
                  placeholder: (c, _) =>
                      Container(color: Colors.grey.shade200),
                  errorWidget: (c, _, e) => const Icon(Icons.broken_image),
                )
              : const Icon(Icons.image_not_supported),
        );
      },
    );
  }
}
