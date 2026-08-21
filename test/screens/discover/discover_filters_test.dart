import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/core/layout/breakpoints.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/models/models.dart';
import 'package:flame/providers/discovery_provider.dart';
import 'package:flame/providers/filter_provider.dart';
import 'package:flame/providers/location_provider.dart';
import 'package:flame/screens/discover/discover_filters_screen.dart';
import 'package:flame/services/discovery_service.dart';
import 'package:flame/services/location_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;

/// Records reloads so a test can prove a failed save did not touch the deck.
class _RecordingDiscovery extends DiscoveryNotifier {
  _RecordingDiscovery() : super(_NoService()) {
    state = const AsyncValue.data(<User>[]);
  }

  int reloads = 0;

  @override
  Future<void> clearAndReload() async {
    reloads++;
  }
}

class _NoService extends DiscoveryService {
  @override
  Future<ServiceResult<DiscoveryResult>> getPotentialMatches({int limit = 10}) async =>
      ServiceResult.success(const DiscoveryResult(users: [], hasMore: false));
}

class _Filters extends FilterNotifier {
  _Filters({required this.succeeds});
  final bool succeeds;
  int saves = 0;

  @override
  Future<bool> savePreferencesToApi() async {
    saves++;
    return succeeds;
  }
}

late _RecordingDiscovery deck;
late _Filters filters;

Future<void> pumpSheet(
  WidgetTester tester, {
  LocationAvailability availability = LocationAvailability.granted,
  bool saveSucceeds = true,
  Size size = const Size(390, 844),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });

  deck = _RecordingDiscovery();
  filters = _Filters(succeeds: saveSucceeds);

  final refresher = LocationRefresher(
    getPosition: () async => availability == LocationAvailability.denied
        ? LocationResult.failure('denied')
        : LocationResult.successAt(1, 2),
    push: (_, __) async => true,
  );
  await refresher.refreshOnce();

  await tester.pumpWidget(ProviderScope(
    overrides: [
      discoveryProvider.overrideWith((ref) => deck),
      filterProvider.overrideWith((ref) => filters),
      locationRefresherProvider.overrideWithValue(refresher),
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
      home: const DiscoverFiltersScreen(),
    ),
  ));
}

/// The Apply button sits below the fold on a phone, so every save test scrolls
/// to it first.
Future<void> tapApply(WidgetTester tester) async {
  final apply = find.text('Apply filters');
  await tester.scrollUntilVisible(apply, 200,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(apply);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the distance slider is disabled, with a reason, without location',
      (tester) async {
    await pumpSheet(tester, availability: LocationAvailability.denied);
    await tester.pumpAndSettle();

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull,
        reason: 'a control that cannot work must not look like one that can');
    expect(find.text('Allow location access to filter by distance'), findsOneWidget);
  });

  testWidgets('the distance slider is live with location', (tester) async {
    await pumpSheet(tester);
    await tester.pumpAndSettle();

    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    expect(find.text('Allow location access to filter by distance'), findsNothing);
  });

  testWidgets('a failed save keeps the sheet open and does not reload the deck',
      (tester) async {
    await pumpSheet(tester, saveSucceeds: false);
    await tester.pumpAndSettle();

    await tapApply(tester);

    expect(find.byType(DiscoverFiltersScreen), findsOneWidget,
        reason: 'it must not look saved when it is not');
    expect(deck.reloads, 0);
  });

  testWidgets('a successful save clears and reloads the deck', (tester) async {
    await pumpSheet(tester);
    await tester.pumpAndSettle();

    await tapApply(tester);

    expect(filters.saves, 1);
    expect(deck.reloads, 1);
  });

  testWidgets('gender and interests are both offered', (tester) async {
    await pumpSheet(tester);
    await tester.pumpAndSettle();

    // Both were hidden behind advancedFiltersEnabled until the query honoured them.
    expect(find.text('Show me'), findsOneWidget);
    expect(find.text('Everyone'), findsOneWidget);
    expect(find.text('Interests'), findsOneWidget);
    expect(find.text('Travel'), findsOneWidget);
  });

  testWidgets('interest chips render without overflow at 2x text scale',
      (tester) async {
    await pumpSheet(tester, textScale: 2.0);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet is width-constrained on a tablet', (tester) async {
    await pumpSheet(tester, size: const Size(1024, 1366));
    await tester.pumpAndSettle();

    final width = tester.getSize(find.byKey(const ValueKey('filters-body'))).width;
    expect(width, lessThanOrEqualTo(kSheetMaxWidth));
  });
}
