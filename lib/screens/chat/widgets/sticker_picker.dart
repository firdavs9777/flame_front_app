import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flame/services/chat_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';

class StickerPicker extends ConsumerStatefulWidget {
  final void Function(Sticker sticker) onStickerSelected;

  const StickerPicker({
    super.key,
    required this.onStickerSelected,
  });

  @override
  ConsumerState<StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends ConsumerState<StickerPicker> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<StickerPack> _myPacks = [];
  List<Sticker> _recentStickers = [];
  final Map<String, List<Sticker>> _packStickers = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStickers();
  }

  Future<void> _loadStickers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final chatService = ref.read(chatServiceProvider);

      // Load recent stickers and my packs in parallel
      final results = await Future.wait([
        chatService.getRecentStickers(),
        chatService.getMyStickerPacks(),
      ]);

      final recentResult = results[0] as ServiceResult<List<Sticker>>;
      final packsResult = results[1] as ServiceResult<List<StickerPack>>;

      if (mounted) {
        setState(() {
          if (recentResult.success && recentResult.data != null) {
            _recentStickers = recentResult.data!;
          }
          if (packsResult.success && packsResult.data != null) {
            _myPacks = packsResult.data!;
          }
          _isLoading = false;

          // Initialize tab controller with recent + packs count
          _tabController = TabController(
            length: 1 + _myPacks.length, // Recent + each pack
            vsync: this,
          );
          _tabController.addListener(() {
            if (!_tabController.indexIsChanging) {
              _onTabChanged(_tabController.index);
            }
          });
        });

        // Load first pack stickers if available
        if (_myPacks.isNotEmpty) {
          _loadPackStickers(_myPacks.first.id);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load stickers';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadPackStickers(String packId) async {
    if (_packStickers.containsKey(packId)) return;

    try {
      final chatService = ref.read(chatServiceProvider);
      final result = await chatService.getStickerPackDetails(packId);

      if (mounted && result.success && result.data != null) {
        setState(() {
          _packStickers[packId] = result.data!.stickers;
        });
      }
    } catch (e) {
      debugPrint('Error loading pack stickers: $e');
    }
  }

  void _onTabChanged(int index) {
    // Load pack stickers if not recent tab and not loaded
    if (index > 0 && index - 1 < _myPacks.length) {
      final packId = _myPacks[index - 1].id;
      _loadPackStickers(packId);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.45,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'Stickers',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _showStickerStore,
                  tooltip: 'Sticker Store',
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorState()
                    : _buildStickerContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _loadStickers,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildStickerContent() {
    if (_myPacks.isEmpty && _recentStickers.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        // Pack tabs
        if (_myPacks.isNotEmpty) ...[
          SizedBox(
            height: 50,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppTheme.primaryColor,
              labelColor: AppTheme.primaryColor,
              unselectedLabelColor: Colors.grey,
              tabs: [
                const Tab(icon: Icon(Icons.access_time, size: 24)),
                ..._myPacks.map((pack) => Tab(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: pack.thumbnailUrl,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.grey[200],
                      ),
                      errorWidget: (_, __, ___) => Icon(
                        Icons.emoji_emotions,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
                )),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRecentStickers(),
                ..._myPacks.map((pack) => _buildPackStickers(pack.id)),
              ],
            ),
          ),
        ] else ...[
          Expanded(child: _buildRecentStickers()),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_emotions_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No stickers yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Browse the sticker store to add some!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _showStickerStore,
            icon: const Icon(Icons.add),
            label: const Text('Browse Stickers'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentStickers() {
    if (_recentStickers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'No recent stickers',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return _buildStickerGrid(_recentStickers);
  }

  Widget _buildPackStickers(String packId) {
    final stickers = _packStickers[packId];

    if (stickers == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (stickers.isEmpty) {
      return Center(
        child: Text(
          'No stickers in this pack',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    return _buildStickerGrid(stickers);
  }

  Widget _buildStickerGrid(List<Sticker> stickers) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, index) {
        final sticker = stickers[index];
        return _StickerItem(
          sticker: sticker,
          onTap: () {
            Navigator.pop(context);
            widget.onStickerSelected(sticker);
          },
        );
      },
    );
  }

  void _showStickerStore() {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StickerStore(
        onPackAdded: () {
          // Reload stickers after adding a pack
          _loadStickers();
        },
      ),
    );
  }
}

class _StickerItem extends StatelessWidget {
  final Sticker sticker;
  final VoidCallback onTap;

  const _StickerItem({
    required this.sticker,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[50],
        ),
        child: CachedNetworkImage(
          imageUrl: sticker.imageUrl.isNotEmpty
              ? sticker.imageUrl
              : sticker.thumbnailUrl,
          fit: BoxFit.contain,
          placeholder: (_, __) => Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.grey[300],
              ),
            ),
          ),
          errorWidget: (_, __, ___) => Icon(
            Icons.broken_image,
            color: Colors.grey[400],
          ),
        ),
      ),
    );
  }
}

// Sticker Store for browsing and adding sticker packs
class StickerStore extends ConsumerStatefulWidget {
  final VoidCallback? onPackAdded;

  const StickerStore({
    super.key,
    this.onPackAdded,
  });

  @override
  ConsumerState<StickerStore> createState() => _StickerStoreState();
}

class _StickerStoreState extends ConsumerState<StickerStore> {
  List<StickerPack> _allPacks = [];
  Set<String> _myPackIds = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  Future<void> _loadStore() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final chatService = ref.read(chatServiceProvider);

      final allPacksResult = await chatService.getStickerPacks();
      final myPacksResult = await chatService.getMyStickerPacks();

      if (mounted) {
        setState(() {
          if (allPacksResult.success && allPacksResult.data != null) {
            _allPacks = allPacksResult.data!;
          }
          if (myPacksResult.success && myPacksResult.data != null) {
            _myPackIds = myPacksResult.data!.map((p) => p.id).toSet();
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load sticker store';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _togglePack(StickerPack pack) async {
    final chatService = ref.read(chatServiceProvider);
    final isAdded = _myPackIds.contains(pack.id);

    if (isAdded) {
      final result = await chatService.removeStickerPack(pack.id);
      if (result.success) {
        setState(() => _myPackIds.remove(pack.id));
      }
    } else {
      final result = await chatService.addStickerPack(pack.id);
      if (result.success) {
        setState(() => _myPackIds.add(pack.id));
        widget.onPackAdded?.call();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Sticker Store',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorState()
                    : _buildPacksList(),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _loadStore,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildPacksList() {
    if (_allPacks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_emotions_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No sticker packs available',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _allPacks.length,
      itemBuilder: (context, index) {
        final pack = _allPacks[index];
        final isAdded = _myPackIds.contains(pack.id);

        return _StickerPackCard(
          pack: pack,
          isAdded: isAdded,
          onToggle: () => _togglePack(pack),
        );
      },
    );
  }
}

class _StickerPackCard extends StatelessWidget {
  final StickerPack pack;
  final bool isAdded;
  final VoidCallback onToggle;

  const _StickerPackCard({
    required this.pack,
    required this.isAdded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: pack.thumbnailUrl,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: Colors.grey[200],
            ),
            errorWidget: (_, __, ___) => Container(
              color: Colors.grey[200],
              child: Icon(Icons.emoji_emotions, color: Colors.grey[400]),
            ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                pack.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (pack.isOfficial) ...[
              const SizedBox(width: 4),
              Icon(Icons.verified, size: 16, color: Colors.blue[400]),
            ],
            if (pack.isPremium) ...[
              const SizedBox(width: 4),
              Icon(Icons.star, size: 16, color: Colors.amber[600]),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pack.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              '${pack.stickerCount} stickers',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: onToggle,
          style: ElevatedButton.styleFrom(
            backgroundColor: isAdded ? Colors.grey[300] : AppTheme.primaryColor,
            foregroundColor: isAdded ? Colors.black87 : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            minimumSize: const Size(80, 36),
          ),
          child: Text(isAdded ? 'Remove' : 'Add'),
        ),
      ),
    );
  }
}
