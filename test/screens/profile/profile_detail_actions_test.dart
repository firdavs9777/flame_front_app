import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/swipe_provider.dart';
import 'package:flame/services/swipe_service.dart';
import 'package:flame/screens/profile/profile_detail_screen.dart';
import 'package:flame/widgets/report_block_menu.dart';

User _user() => User.fromJson({'id': 'u1', 'name': 'Bea', 'photos': <dynamic>[]});

class _RecordingSwipe extends SwipeNotifier {
  _RecordingSwipe(Ref ref) : super(SwipeService(), ref);

  final List<String> calls = [];
  String? failWith;

  @override
  Future<String?> like(User user) async {
    calls.add('like:${user.id}');
    return failWith;
  }

  @override
  Future<String?> superLike(User user) async {
    calls.add('super:${user.id}');
    return failWith;
  }
}

late _RecordingSwipe swipe;

Future<void> pumpDetail(WidgetTester tester,
    {bool isPreview = false, String? failWith}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      swipeProvider.overrideWith((ref) {
        swipe = _RecordingSwipe(ref)..failWith = failWith;
        return swipe;
      }),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: kSupportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: ProfileDetailScreen(user: _user(), isPreview: isPreview),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('like calls the swipe provider', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    expect(swipe.calls, ['like:u1']);
  });

  testWidgets('super-like calls the swipe provider', (tester) async {
    await pumpDetail(tester);

    await tester.tap(find.byIcon(Icons.star));
    await tester.pumpAndSettle();

    expect(swipe.calls, ['super:u1']);
  });

  testWidgets('a failed like reports and does not pop', (tester) async {
    await pumpDetail(tester, failWith: 'no likes left');

    await tester.tap(find.byIcon(Icons.favorite));
    await tester.pumpAndSettle();

    expect(find.text('no likes left'), findsOneWidget);
    expect(find.byType(ProfileDetailScreen), findsOneWidget);
  });

  testWidgets('preview hides every action you cannot take on yourself',
      (tester) async {
    await pumpDetail(tester, isPreview: true);

    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.byType(ReportBlockMenu), findsNothing,
        reason: 'you cannot report or block yourself');
  });

  testWidgets('the flag defaults false so existing call sites are unchanged',
      (tester) async {
    await pumpDetail(tester);

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byType(ReportBlockMenu), findsOneWidget);
  });
}
