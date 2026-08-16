import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_test/flutter_test.dart';

// CardSwiper keeps its own current index internally (advanced by swipes, not
// by the widget tree). Until now the deck never shrank, so the index never
// outran the list. With Discover excluding already-swiped users, the deck
// genuinely empties: the index can be left pointing past the end of a
// shrunk backing list, and an unguarded `cardBuilder` throws RangeError.
//
// To reproduce, we must first advance CardSwiper's internal index (via the
// controller, mimicking a user having swiped past the first card) and only
// then shrink the backing list — shrinking alone, with the index still at 0,
// does not trigger the bug.
void main() {
  testWidgets('cardBuilder is never called with an out-of-range index',
      (tester) async {
    final users = <String>['a', 'b', 'c'];
    final controller = CardSwiperController();

    Widget build() => MaterialApp(
          home: Scaffold(
            body: CardSwiper(
              controller: controller,
              cardsCount: users.length,
              numberOfCardsDisplayed: users.length > 2 ? 3 : users.length,
              cardBuilder: (context, index, px, py) {
                if (index < 0 || index >= users.length) {
                  return const SizedBox.shrink();
                }
                return Text(users[index]);
              },
            ),
          ),
        );

    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    // Advance the swiper's internal current index to the last card (2) while
    // the list still has 3 elements — a valid move at the time it happens.
    controller.moveTo(2);
    await tester.pump();
    await tester.pumpAndSettle();

    // Shrink the deck to one item and rebuild, mimicking the provider
    // emitting a shorter list (post swipe-exclusion) while the swiper's
    // internal index is still 2.
    users.removeRange(1, users.length);
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'a shrinking deck must not throw RangeError');
  });
}
