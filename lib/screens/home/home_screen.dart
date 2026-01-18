import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/profile_card.dart';
import 'package:flame/widgets/action_buttons.dart';
import 'package:flame/screens/profile/profile_detail_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final CardSwiperController _swiperController = CardSwiperController();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        ref.read(discoveryProvider.notifier).loadPotentialMatches(refresh: true);
      }
    });
  }

  @override
  void dispose() {
    _swiperController.dispose();
    super.dispose();
  }

  void _onSwipe(int previousIndex, int? currentIndex, CardSwiperDirection direction) {
    final usersState = ref.read(discoveryProvider);
    final users = usersState.valueOrNull ?? [];
    if (previousIndex >= users.length) return;

    final user = users[previousIndex];

    if (direction == CardSwiperDirection.right) {
      _handleLike(user);
    } else if (direction == CardSwiperDirection.left) {
      _handleDislike(user);
    } else if (direction == CardSwiperDirection.top) {
      _handleSuperLike(user);
    }
  }

  Future<void> _handleLike(User user) async {
    final success = await ref.read(swipeProvider.notifier).like(user);
    if (success) {
      final swipeState = ref.read(swipeProvider);
      if (swipeState.newMatch != null) {
        _showMatchDialog(user, swipeState.newMatch!);
      }
    }
  }

  Future<void> _handleDislike(User user) async {
    await ref.read(swipeProvider.notifier).pass(user);
  }

  Future<void> _handleSuperLike(User user) async {
    final success = await ref.read(swipeProvider.notifier).superLike(user);
    if (success) {
      final swipeState = ref.read(swipeProvider);
      if (swipeState.newMatch != null) {
        _showMatchDialog(user, swipeState.newMatch!);
      }
    }
  }

  void _showMatchDialog(User user, Match match) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primaryColor,
                AppTheme.secondaryColor,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "It's a Match!",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'You and ${user.name} liked each other',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 50,
                backgroundImage: NetworkImage(user.primaryPhoto),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () {
                      ref.read(swipeProvider.notifier).clearNewMatch();
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Keep Swiping',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      ref.read(swipeProvider.notifier).clearNewMatch();
                      Navigator.pop(context);
                      // Navigate to chat - load conversations first
                      ref.read(conversationsProvider.notifier).loadConversations(refresh: true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primaryColor,
                    ),
                    child: const Text('Send Message'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usersState = ref.watch(discoveryProvider);
    final swipeState = ref.watch(swipeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_fire_department,
              color: AppTheme.primaryColor,
              size: 32,
            ),
            const SizedBox(width: 8),
            const Text(
              'Flame',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () {
              Navigator.pushNamed(context, '/discover');
            },
          ),
        ],
      ),
      body: usersState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 60, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text('Failed to load profiles', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    ref.read(discoveryProvider.notifier).loadPotentialMatches(refresh: true);
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (users) {
          if (users.isEmpty) {
            return _buildEmptyState();
          }
          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CardSwiper(
                        controller: _swiperController,
                        cardsCount: users.length,
                        numberOfCardsDisplayed: users.length > 2 ? 3 : users.length,
                        backCardOffset: const Offset(0, 40),
                        padding: EdgeInsets.zero,
                        onSwipe: (prev, curr, dir) {
                          _onSwipe(prev, curr, dir);
                          return true;
                        },
                        onEnd: () {
                          // Load more when cards run out
                          ref.read(discoveryProvider.notifier).loadMore();
                        },
                        cardBuilder: (context, index, percentX, percentY) {
                          return ProfileCard(
                            user: users[index],
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProfileDetailScreen(user: users[index]),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: ActionButtons(
                      onDislike: () => _swiperController.swipe(CardSwiperDirection.left),
                      onSuperLike: () => _swiperController.swipe(CardSwiperDirection.top),
                      onLike: () => _swiperController.swipe(CardSwiperDirection.right),
                    ),
                  ),
                ],
              ),
              if (swipeState.isLoading)
                Container(
                  color: Colors.black26,
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 20),
          Text(
            'No more profiles',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Check back later or adjust your filters',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              ref.read(discoveryProvider.notifier).loadPotentialMatches(refresh: true);
            },
            child: const Text('Refresh'),
          ),
        ],
      ),
    );
  }
}
