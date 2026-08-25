import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/screens/auth/registration/step_wizard.dart';

/// Two trivial steps: each renders its name and a button that advances.
List<WizardStep> _steps({VoidCallback? onLastNext}) => [
      WizardStep(
        title: 'First',
        subtitle: 'the first one',
        builder: (context, onNext) => Column(
          children: [
            const Text('step-one-body'),
            ElevatedButton(onPressed: onNext, child: const Text('next-1')),
          ],
        ),
      ),
      WizardStep(
        title: 'Second',
        subtitle: 'the second one',
        builder: (context, onNext) => Column(
          children: [
            const Text('step-two-body'),
            ElevatedButton(onPressed: onNext, child: const Text('next-2')),
          ],
        ),
      ),
    ];

Widget _host({
  required List<WizardStep> steps,
  Future<void> Function()? onComplete,
  VoidCallback? onExit,
  void Function(int)? onStepChanged,
  GlobalKey<StepWizardState>? wizardKey,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: kSupportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: StepWizard(
      key: wizardKey,
      steps: steps,
      onComplete: onComplete ?? () async {},
      onExit: onExit,
      onStepChanged: onStepChanged,
    ),
  );
}

void main() {
  testWidgets('opens on the first step and shows its title and subtitle',
      (tester) async {
    await tester.pumpWidget(_host(steps: _steps()));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('First'), findsOneWidget);
    expect(find.text('the first one'), findsOneWidget);
    expect(find.text('step-one-body'), findsOneWidget);
    expect(find.text('Step 1 of 2'), findsOneWidget);
  });

  testWidgets('onNext advances and updates the header', (tester) async {
    await tester.pumpWidget(_host(steps: _steps()));

    await tester.tap(find.text('next-1'));
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Step 2 of 2'), findsOneWidget);
  });

  testWidgets('back returns to the previous step', (tester) async {
    await tester.pumpWidget(_host(steps: _steps()));

    await tester.tap(find.text('next-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('back on the first step calls onExit instead', (tester) async {
    var exited = false;
    await tester.pumpWidget(
      _host(steps: _steps(), onExit: () => exited = true),
    );

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(exited, isTrue);
    expect(find.text('First'), findsOneWidget);
  });

  testWidgets('onNext on the LAST step calls onComplete, not a page turn',
      (tester) async {
    var completed = 0;
    await tester.pumpWidget(
      _host(steps: _steps(), onComplete: () async => completed++),
    );

    await tester.tap(find.text('next-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('next-2'));
    await tester.pumpAndSettle();

    expect(completed, 1);
  });

  testWidgets('onComplete cannot be entered twice concurrently',
      (tester) async {
    var completed = 0;
    final gate = Completer<void>();
    await tester.pumpWidget(
      _host(
        steps: _steps(),
        onComplete: () async {
          completed++;
          await gate.future;
        },
      ),
    );

    await tester.tap(find.text('next-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('next-2'));
    await tester.pump();
    await tester.tap(find.text('next-2'));
    await tester.pump();

    expect(completed, 1);
    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('onStepChanged fires with each new index', (tester) async {
    final seen = <int>[];
    await tester.pumpWidget(
      _host(steps: _steps(), onStepChanged: seen.add),
    );

    await tester.tap(find.text('next-1'));
    await tester.pumpAndSettle();

    expect(seen, [1]);
  });

  testWidgets('jumpToStep moves without animating through the middle',
      (tester) async {
    final key = GlobalKey<StepWizardState>();
    await tester.pumpWidget(_host(steps: _steps(), wizardKey: key));

    key.currentState!.jumpToStep(1);
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
  });
}
