import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/profile_card.dart';
import 'package:flame/widgets/action_buttons.dart';
import 'package:flame/screens/profile/profile_detail_screen.dart';
import 'package:flame/screens/discover/widgets/deck_states.dart';
import 'package:flame/core/layout/breakpoints.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final CardSwiperController _swiperController = CardSwiperController();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        ref.read(discoveryProvider.notifier).load(refresh: true);
      }
    });
  }

  @override
  void dispose() {
    _swiperController.dispose();
    super.dispose();
  }

  void _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
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

    // Top up before the deck visibly empties. onEnd alone fires only once the
    // last card is gone, which shows the user a loading state they did not need
    // to see. `refill` no-ops while a fetch is in flight or the server has said
    // there is no more, so calling it on every swipe is cheap.
    final remaining = previousIndex >= 0 ? users.length - previousIndex - 1 : 0;
    if (remaining <= DiscoveryNotifier.refillThreshold) {
      ref.read(discoveryProvider.notifier).refill();
    }
  }

  Future<void> _handleLike(User user) async {
    final error = await ref.read(swipeProvider.notifier).like(user);
    if (error != null) {
      _showSwipeError(error);
      return;
    }
    final swipeState = ref.read(swipeProvider);
    if (swipeState.newMatch != null) {
      _showMatchDialog(user, swipeState.newMatch!);
    }
  }

  Future<void> _handleDislike(User user) async {
    final error = await ref.read(swipeProvider.notifier).pass(user);
    if (error != null) {
      _showSwipeError(error);
    }
  }

  Future<void> _handleSuperLike(User user) async {
    final error = await ref.read(swipeProvider.notifier).superLike(user);
    if (error != null) {
      _showSwipeError(error);
      return;
    }
    final swipeState = ref.read(swipeProvider);
    if (swipeState.newMatch != null) {
      _showMatchDialog(user, swipeState.newMatch!);
    }
  }

  void _showSwipeError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red[400]),
    );
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
              colors: [AppTheme.primaryColor, AppTheme.secondaryColor],
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
                style: const TextStyle(color: Colors.white70, fontSize: 16),
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
                  Flexible(
                    child: TextButton(
                      onPressed: () {
                        ref.read(swipeProvider.notifier).clearNewMatch();
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Keep Swiping',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: ElevatedButton(
                      onPressed: () {
                        ref.read(swipeProvider.notifier).clearNewMatch();
                        Navigator.pop(context);
                        // Navigate to chat - load conversations first
                        ref
                            .read(conversationsProvider.notifier)
                            .loadConversations(refresh: true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.primaryColor,
                      ),
                      child: const Text('Send Message'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _reload() => ref.read(discoveryProvider.notifier).load(refresh: true);

  void _openFilters() => Navigator.pushNamed(context, '/discover/filters');

  /// Whether the user has narrowed the deck themselves.
  ///
  /// Decides between "no one matches these filters" and "you've seen everyone":
  /// offering to relax filters that are not set would be nonsense.
  bool get _filtersActive {
    final user = ref.read(currentUserProvider).valueOrNull;
    if (user == null) return false;
    return user.minAgePreference != 18 ||
        user.maxAgePreference != 50 ||
        user.interestsFilter.isNotEmpty ||
        user.lookingFor != Gender.other;
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
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () {
              _openFilters();
            },
          ),
        ],
      ),
      body: usersState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            DeckError(error: error.toString(), onRetry: _reload),
        data: (users) {
          if (users.isEmpty) {
            // Which fact is true matters: one is actionable and one is not.
            return _filtersActive
                ? DeckEmptyForFilters(onRelaxFilters: _openFilters)
                : DeckSeenEveryone(onRefresh: _reload);
          }
          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        // A full-bleed swipe card on a tablet is absurd; the deck
                        // stays phone-sized and centres itself.
                        constraints: const BoxConstraints(
                          maxWidth: kDeckMaxWidth,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: CardSwiper(
                            controller: _swiperController,
                            cardsCount: users.length,
                            numberOfCardsDisplayed: users.length > 2
                                ? 3
                                : users.length,
                            backCardOffset: const Offset(0, 40),
                            padding: EdgeInsets.zero,
                            onSwipe: (prev, curr, dir) {
                              _onSwipe(prev, curr, dir);
                              return true;
                            },
                            onEnd: () {
                              // Load more when cards run out
                              ref.read(discoveryProvider.notifier).refill();
                            },
                            cardBuilder: (context, index, percentX, percentY) {
                              // CardSwiper holds its own index; when the deck shrinks
                              // (Discover now excludes swiped users, so it genuinely
                              // empties) that index can outrun the list. Render
                              // nothing rather than throwing RangeError.
                              if (index < 0 || index >= users.length) {
                                return const SizedBox.shrink();
                              }
                              final user = users[index];
                              return ProfileCard(
                                user: user,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ProfileDetailScreen(user: user),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: ActionButtons(
                      onDislike: () =>
                          _swiperController.swipe(CardSwiperDirection.left),
                      onSuperLike: () =>
                          _swiperController.swipe(CardSwiperDirection.top),
                      onLike: () =>
                          _swiperController.swipe(CardSwiperDirection.right),
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
}
