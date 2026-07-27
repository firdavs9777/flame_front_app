import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/models/story.dart';
import 'package:flame/screens/stories/story_viewer_screen.dart';
import 'package:flame/screens/stories/widgets/story_progress_bar.dart';

// 1x1 transparent PNG as a data URI so the viewer renders without network.
const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

Story _story(String id, String caption) {
  final created = DateTime.now().subtract(const Duration(hours: 1));
  return Story(
    id: id,
    userId: 'u1',
    mediaUrl: _png,
    caption: caption,
    createdAt: created,
    expiresAt: created.add(const Duration(hours: 24)),
  );
}

Future<void> _pumpViewer(WidgetTester tester) async {
  final users = [
    UserStories(
      userId: 'u1',
      name: 'Ann',
      avatarUrl: '',
      stories: [_story('s0', 'first'), _story('s1', 'second')],
    ),
  ];
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: StoryViewerScreen(users: users, initialUserIndex: 0),
      ),
    ),
  );
  await tester.pump(); // fire the post-frame _start()
}

void main() {
  testWidgets('shows the first story with a segmented progress bar', (tester) async {
    await _pumpViewer(tester);

    expect(find.byType(StoryProgressBar), findsOneWidget);
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsNothing);
  });

  testWidgets('tapping the right zone advances to the next story', (tester) async {
    await _pumpViewer(tester);

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    await tester.tapAt(Offset(size.width * 0.8, size.height * 0.5));
    await tester.pump();

    expect(find.text('second'), findsOneWidget);
    expect(find.text('first'), findsNothing);
  });
}
