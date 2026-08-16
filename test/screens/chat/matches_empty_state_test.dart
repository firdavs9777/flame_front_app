import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/screens/chat/widgets/matches_empty_state.dart';

// The empty state sits in a SliverFillRemaining under the "New Matches" strip,
// so the height it actually gets is whatever that strip leaves behind — as
// little as ~142px on a phone. Its content is taller than that, which produced
// a RenderFlex overflow in production:
//
//   A RenderFlex overflowed by 13 pixels on the bottom.
//
// It must degrade instead of overflowing, at any height.
void main() {
  Widget host(double height) => MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: 600 - height)),
          const SliverFillRemaining(
            hasScrollBody: false,
            child: MatchesEmptyState(),
          ),
        ],
      ),
    ),
  );

  testWidgets('does not overflow in the cramped height that broke production', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 142.4px is the exact constraint from the production stack trace.
    await tester.pumpWidget(host(142.4));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('does not overflow when almost no room is left', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(host(60));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('still centres when there is plenty of room', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(host(600));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No messages yet'), findsOneWidget);
    expect(find.text('Match with someone to start chatting!'), findsOneWidget);
  });
}
