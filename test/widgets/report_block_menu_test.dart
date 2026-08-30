import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/services/report_service.dart';
import 'package:flame/services/user_service.dart'; // ServiceResult lives here
import 'package:flame/providers/report_provider.dart';
import 'package:flame/widgets/report_block_menu.dart';

class _FakeReportService extends ReportService {
  String? reportedUserId;
  ReportReason? reportedReason;
  String? reportedMessageId;
  String? blockedUserId;

  @override
  Future<ServiceResult<void>> reportUser({
    required String userId,
    required ReportReason reason,
    String? details,
    String? messageId,
  }) async {
    reportedUserId = userId;
    reportedReason = reason;
    reportedMessageId = messageId;
    return ServiceResult.success(null);
  }

  @override
  Future<ServiceResult<void>> blockUser(String userId) async {
    blockedUserId = userId;
    return ServiceResult.success(null);
  }
}

Widget _host(_FakeReportService fake) => ProviderScope(
      overrides: [reportServiceProvider.overrideWithValue(fake)],
      // Localised host: the menu reads its labels from the ARBs now, so a bare
      // MaterialApp would throw looking for AppLocalizations.
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Center(
            child: ReportBlockMenu(userId: 'u1', userName: 'Ann'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('Report → pick a reason calls reportUser with that reason', (tester) async {
    final fake = _FakeReportService();
    await tester.pumpWidget(_host(fake));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    // Reason sheet lists every ReportReason, labelled from the ARBs.
    expect(find.text('Spam or scam'), findsOneWidget);
    await tester.tap(find.text('Spam or scam'));
    await tester.pumpAndSettle();

    expect(fake.reportedUserId, 'u1');
    expect(fake.reportedReason, ReportReason.spam);
    expect(fake.reportedMessageId, isNull,
        reason: 'reporting from the profile menu reports the person, '
            'not a single message');
  });

  testWidgets('Block → confirm calls blockUser', (tester) async {
    final fake = _FakeReportService();
    await tester.pumpWidget(_host(fake));

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();

    // Confirm dialog: title 'Block Ann?', action button 'Block'.
    expect(find.text('Block Ann?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Block'));
    await tester.pumpAndSettle();

    expect(fake.blockedUserId, 'u1');
  });
}
