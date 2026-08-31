import 'package:flame/core/image/photo_variants.dart';
import 'package:flame/models/user.dart';

/// How many cards ahead of the visible one to warm.
///
/// Two, not more: the deck refills at three remaining
/// (`DiscoveryNotifier.refillThreshold`), so warming further ahead would fetch
/// images for cards that may never be reached.
const int kPrefetchDepth = 2;

/// The image URLs worth warming, given the card currently on top.
///
/// Pure so it can be tested without an element tree — `precacheImage` needs
/// both a real context and a network.
List<String> urlsToPrefetch(List<User> deck, {required int currentIndex}) {
  final urls = <String>[];
  for (var i = currentIndex + 1; i <= currentIndex + kPrefetchDepth; i++) {
    if (i < 0 || i >= deck.length) break;
    final photos = deck[i].photos;
    if (photos.isEmpty) continue;
    // A card is full-bleed, so it wants the same variant the card itself draws.
    urls.add(photoUrlFor(photos.first, PhotoSize.full));
  }
  return urls;
}
