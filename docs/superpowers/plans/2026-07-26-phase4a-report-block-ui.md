# Phase 4a — Report / Block UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give users a reachable way to **report** and **block** another user — the App Store guideline 1.2 / Play UGC-safety requirement for a dating app. `ReportService` is fully built but has zero callers today.

**Architecture:** A self-contained `ReportBlockMenu` (a `ConsumerWidget` overflow menu) that offers Report (a reason picker) and Block (a confirm dialog), calling `ReportService` through a new `reportServiceProvider`. It is dropped into `ProfileDetailScreen`'s app bar — the profile view reachable from both the Discover deck and chat. New files only, so none of the user's dirty working-tree files are touched.

**Tech Stack:** Flutter, Dart, Riverpod, `flutter_test`. No new dependencies.

## Global Constraints

- API base (prod): `https://api.banatalk.com/flamebackend/v1`. Endpoints already implemented in `ReportService` (`report_service.dart`): `POST /reports` (body `{user_id, reason, details?}`), `POST /blocks` (`{user_id}`), `DELETE /blocks/:id`, `GET /blocks`.
- `ReportReason` enum (`report_service.dart:68`) has `.displayName` (UI) and `.toApiString()` (wire). Reuse it; do not redefine reasons.
- Do NOT edit `lib/providers/providers.dart` (dirty working tree) — put the new provider in a new file. Do NOT edit `story_viewer_screen.dart` (untracked user work) — story-level reporting is out of scope here.
- Capture `ScaffoldMessenger` / `Navigator` from context BEFORE any `await`, then guard with `if (!context.mounted) return;` — do not use a context across an async gap (this repo's analyzer enforces `use_build_context_synchronously`).
- Strings may be plain English (this screen is not yet localized); localization is a tracked follow-up, not part of this plan.
- Commands: `flutter test <path>`, `flutter analyze <paths>`.

**Deferred (tracked, not here):** story-viewer reporting (Phase 4, when the stories files are committed); report/block from the Discover card (`profile_card.dart` is dirty); a "Blocked users" management screen in Settings.

---

### Task 1: Report/Block menu widget + provider

**Files:**
- Create: `lib/providers/report_provider.dart`
- Create: `lib/widgets/report_block_menu.dart`
- Test: `test/widgets/report_block_menu_test.dart`

**Interfaces:**
- Produces: `reportServiceProvider` (`Provider<ReportService>`).
- Produces: `ReportBlockMenu({required String userId, String userName})` — a `ConsumerWidget`
  rendering a `PopupMenuButton` (`Icons.more_vert`) with "Report" and "Block". Report opens a
  reason bottom sheet (one row per `ReportReason`); choosing one calls `reportUser` and shows a
  SnackBar. Block opens a confirm dialog; confirming calls `blockUser`, shows a SnackBar, and pops
  the current route if possible.

- [ ] **Step 1: Write the failing test**

Create `test/widgets/report_block_menu_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/services/report_service.dart';
import 'package:flame/services/user_service.dart'; // ServiceResult lives here
import 'package:flame/providers/report_provider.dart';
import 'package:flame/widgets/report_block_menu.dart';

class _FakeReportService extends ReportService {
  String? reportedUserId;
  ReportReason? reportedReason;
  String? blockedUserId;

  @override
  Future<ServiceResult<void>> reportUser({
    required String userId,
    required ReportReason reason,
    String? details,
  }) async {
    reportedUserId = userId;
    reportedReason = reason;
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
      child: const MaterialApp(
        home: Scaffold(
          appBar: null,
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

    // Reason sheet lists every ReportReason by displayName.
    expect(find.text('Spam'), findsOneWidget);
    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();

    expect(fake.reportedUserId, 'u1');
    expect(fake.reportedReason, ReportReason.spam);
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widgets/report_block_menu_test.dart`
Expected: FAIL — `reportServiceProvider` / `ReportBlockMenu` do not exist (compile error).

- [ ] **Step 3: Create the provider**

Create `lib/providers/report_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/services/report_service.dart';

/// Provides the report/block service. Overridable in tests.
final reportServiceProvider = Provider<ReportService>((ref) => ReportService());
```

- [ ] **Step 4: Create the widget**

Create `lib/widgets/report_block_menu.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/services/report_service.dart';
import 'package:flame/providers/report_provider.dart';

/// Overflow menu offering Report (with a reason) and Block for another user.
/// Reachable wherever a user's profile is shown.
class ReportBlockMenu extends ConsumerWidget {
  final String userId;
  final String userName;

  const ReportBlockMenu({super.key, required this.userId, this.userName = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'report') {
          _showReportSheet(context, ref);
        } else if (value == 'block') {
          _confirmBlock(context, ref);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem<String>(value: 'report', child: Text('Report')),
        PopupMenuItem<String>(value: 'block', child: Text('Block')),
      ],
    );
  }

  void _showReportSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Report this user',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            for (final reason in ReportReason.values)
              ListTile(
                title: Text(reason.displayName),
                onTap: () => _submitReport(context, ref, sheetContext, reason),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport(
    BuildContext context,
    WidgetRef ref,
    BuildContext sheetContext,
    ReportReason reason,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(sheetContext); // close the sheet (sync, pre-await)
    final result =
        await ref.read(reportServiceProvider).reportUser(userId: userId, reason: reason);
    messenger.showSnackBar(SnackBar(
      content: Text(result.success
          ? 'Report submitted. Thank you.'
          : 'Could not submit report'),
    ));
  }

  Future<void> _confirmBlock(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block ${userName.isEmpty ? 'this user' : userName}?'),
        content: const Text("You won't see each other anymore."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final result = await ref.read(reportServiceProvider).blockUser(userId);
    messenger.showSnackBar(SnackBar(
      content: Text(result.success ? 'User blocked' : 'Could not block user'),
    ));
    if (result.success && navigator.canPop()) {
      navigator.pop();
    }
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/widgets/report_block_menu_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Analyze**

Run: `flutter analyze lib/providers/report_provider.dart lib/widgets/report_block_menu.dart test/widgets/report_block_menu_test.dart`
Expected: No issues (in particular, no `use_build_context_synchronously` — messenger/navigator are
captured before the awaits and `context.mounted` guards the gap after the dialog).

- [ ] **Step 7: Commit**

```bash
git add lib/providers/report_provider.dart lib/widgets/report_block_menu.dart test/widgets/report_block_menu_test.dart
git commit -m "feat(safety): reusable Report/Block menu wired to ReportService

Adds reportServiceProvider and a ConsumerWidget overflow menu offering
Report (reason picker) and Block (confirm), calling the existing but
previously-uncalled ReportService. Reachable UI is added in the next task."
```

---

### Task 2: Add the menu to the profile detail screen

**Files:**
- Modify: `lib/screens/profile/profile_detail_screen.dart`

**Interfaces:**
- Consumes: `ReportBlockMenu` (Task 1). `ReportBlockMenu` is a `ConsumerWidget`, so
  `ProfileDetailScreen` does NOT need to become a Consumer.

- [ ] **Step 1: Implement**

In `lib/screens/profile/profile_detail_screen.dart`:

1. Add the import: `import 'package:flame/widgets/report_block_menu.dart';`
2. Add an `actions:` list to the `SliverAppBar` (which currently has `leading:` but no `actions:`).
   Place it right after the `leading:` IconButton block:

```dart
            actions: [
              ReportBlockMenu(
                userId: widget.user.id,
                userName: widget.user.name,
              ),
            ],
```

Do not change anything else in the file.

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/screens/profile/profile_detail_screen.dart`
Expected: No new issues.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/profile/profile_detail_screen.dart
git commit -m "feat(safety): expose Report/Block from the profile detail screen

Adds the ReportBlockMenu to the profile detail app bar, giving a reachable
report/block path from every profile opened via Discover or chat."
```

---

### Task 3: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Full test suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 2: Analyze the project**

Run: `flutter analyze`
Expected: No NEW issues in the files this phase touched (`report_provider.dart`,
`report_block_menu.dart`, `profile_detail_screen.dart`, and the new test). Pre-existing unrelated
lints are acceptable.

- [ ] **Step 3: Commit any fixups**

```bash
git add -A && git commit -m "test: fixups for phase-4a report/block"
```

(Skip if nothing needed. If committing, stage ONLY files this phase touched.)

---

## Self-Review

**Spec coverage (Phase 4, spec §5-M — report/block UI, the store-safety gate):** a reachable
report + block path wired to `ReportService` → Tasks 1-2. ✅ Story-viewer reporting and a blocked-
users screen are explicitly deferred (story files uncommitted; not required for the core gate). ✅

**Placeholder scan:** No TBD/TODO — full widget code and test provided. ✅

**Type consistency:** `reportServiceProvider` is `Provider<ReportService>` in the provider file,
the override, and the widget's `ref.read`. `ReportBlockMenu({required String userId, String
userName})` matches its definition, the test, and the Task 2 call site. `ReportReason` and
`ReportService` come from `report_service.dart`; `ServiceResult` comes from `user_service.dart`
(the test imports both, so the fake's `ServiceResult<void>` overrides resolve). ✅

**Context-safety:** every post-await `context` use is preceded by a captured messenger/navigator
and a `context.mounted` guard — the exact defect that surfaced in Phase 3 is pre-empted here. ✅
