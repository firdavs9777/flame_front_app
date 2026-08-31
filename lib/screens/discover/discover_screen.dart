import 'package:flame/core/navigation/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flame/core/i18n/build_context_ext.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/providers.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/profile_card.dart';
import 'package:flame/widgets/action_buttons.dart';
import 'package:flame/screens/discover/widgets/deck_states.dart';
import 'package:flame/core/layout/breakpoints.dart';
import 'package:flame/theme/app_tokens.dart';
import 'package:flame/providers/location_provider.dart';
import 'package:flame/core/image/avatar_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flame/screens/discover/deck_prefetch.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final CardSwiperController _swiperController = CardSwiperController();

  /// Bumped whenever the deck is replaced rather than topped up.
  ///
  /// CardSwiper's cursor survives a `cardsCount` change, so a reloaded deck
  /// would be walked from wherever the old one left off. Keying the widget on
  /// this gives a replaced deck a fresh State, and therefore a cursor at zero.
  int _deckGeneration = 0;

  /// Set when the last card has been swiped and nothing more arrived.
  ///
  /// The deck no longer empties itself — swiped cards stay behind the cursor —
  /// so `users.isEmpty` can no longer mean "you have seen everyone".
  bool _deckExhausted = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) {
        _initialized = true;
        // Not awaited, and deliberately started before the deck loads: location
        // is enrichment, so the deck must never wait on it. refreshOnce no-ops
        // after the first call in a session.
        ref.read(locationRefresherProvider).refreshOnce();
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

    _prefetchAhead(users, currentIndex ?? previousIndex + 1);
  }

  /// Warms the images of the cards just behind the visible one.
  ///
  /// Without this, a card's photo starts downloading when it becomes visible,
  /// which is the moment it is too late.
  void _prefetchAhead(List<User> deck, int currentIndex) {
    for (final url in urlsToPrefetch(deck, currentIndex: currentIndex)) {
      // Fire and forget: a failed prefetch costs nothing, and the card's own
      // CachedNetworkImage will fetch it again when it is actually shown.
      precacheImage(CachedNetworkImageProvider(url), context)
          .catchError((Object _) {});
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

  /// Takes back the last swipe, then steps the deck's cursor back one.
  ///
  /// The deck list is untouched: it is append-only now, so the card is still
  /// there — the swiper simply moves back onto it. Putting the user back into
  /// the list, which is what the old undo did, would duplicate them.
  Future<void> _handleUndo() async {
    final outcome = await ref.read(swipeProvider.notifier).undo();
    if (!mounted) return;

    if (outcome == UndoOutcome.undone) {
      _swiperController.undo();
      return;
    }

    final l10n = context.l10n;
    _showSwipeError(switch (outcome) {
      UndoOutcome.nothingToUndo => l10n.deckUndoNothing,
      UndoOutcome.premiumOnly => l10n.deckUndoPremiumOnly,
      UndoOutcome.alreadyMessaged => l10n.deckUndoAlreadyMessaged,
      _ => l10n.errorGeneric,
    });
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
              Text(
                context.l10n.matchItsAMatch,
                style: TextStyle(
                  color: context.onOverlay,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                context.l10n.matchLikedEachOther(user.name),
                style: TextStyle(
                  color: context.onOverlay.withValues(alpha: 0.7),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 50,
                // Was NetworkImage, which has no disk cache at all and
                // refetched the full-size photo on every rebuild.
                backgroundImage: avatarProviderFor(
                  user.primaryPhoto,
                  diameter: 100,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                ),
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
                      child: Text(
                        context.l10n.matchKeepSwiping,
                        style: TextStyle(
                          color: context.onOverlay.withValues(alpha: 0.7),
                        ),
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
                        backgroundColor: context.onOverlay,
                        foregroundColor: AppTheme.primaryColor,
                      ),
                      child: Text(context.l10n.discoverSendMessage),
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

  /// Replaces the deck and restarts the swiper at the top of it.
  void _reload() {
    setState(() {
      _deckGeneration++;
      _deckExhausted = false;
    });
    ref.read(discoveryProvider.notifier).load(refresh: true);
  }

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
    // Warm the cards behind the top one whenever the deck changes, so the
    // second card is ready before the first swipe rather than after it.
    ref.listen(discoveryProvider, (_, next) {
      final deck = next.valueOrNull;
      if (deck != null && deck.isNotEmpty) {
        _prefetchAhead(deck, ref.read(currentCardIndexProvider));
      }
    });

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
          if (users.isEmpty || _deckExhausted) {
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
                            // A replaced deck gets a fresh cursor; a topped-up
                            // one keeps walking the same list.
                            key: ValueKey(_deckGeneration),
                            controller: _swiperController,
                            cardsCount: users.length,
                            // Looping would silently re-show cards the user has
                            // already swiped, and makes "you have seen
                            // everyone" unreachable.
                            isLoop: false,
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
                              // The last card is gone. `_onSwipe` tops the deck
                              // up well before this, so reaching it means the
                              // server had nothing left to give.
                              if (mounted) {
                                setState(() => _deckExhausted = true);
                              }
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
                                  Navigator.pushNamed(
                                    context,
                                    AppRoutes.profileDetail,
                                    arguments: ProfileDetailArgs(user: user),
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
                      onUndo: swipeState.canUndo ? _handleUndo : null,
                    ),
                  ),
                ],
              ),
              if (swipeState.isLoading)
                Container(
                  color: context.viewerScrim.withValues(alpha: 0.15),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          );
        },
      ),
    );
  }
}
