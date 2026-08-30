import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flame/l10n/gen/app_localizations.dart';
import 'package:flame/core/i18n/supported_locales.dart';
import 'package:flame/screens/auth/registration/step_wizard.dart';
import 'package:flame/widgets/kit/kit.dart';

// Two of the store's locales are right-to-left: Arabic and Urdu. Urdu is the
// easy one to miss — it reads RTL like Arabic but sits next to Hindi in most
// language lists.
//
// Flutter mirrors layout automatically, but only for direction-AWARE widgets.
// `EdgeInsets.only(right:)` is absolute: it means "the right edge of the
// screen" in every language, so a trailing gap lands on the leading side once
// the page flips. `EdgeInsetsDirectional.only(end:)` means "the trailing edge"
// and follows the text.
//
// These pin the two places where the spacing carries meaning rather than
// decoration: the wizard's progress row (a mirrored gap makes it read
// back-to-front) and the kit input's trailing affordance.

/// Locale stays 'en' deliberately. What is under test is whether these widgets
/// respond to text DIRECTION — Arabic strings are Phase B and would only make
/// the delegate fail to resolve here.
Widget _host(TextDirection direction, Widget child) => MaterialApp(
      locale: const Locale('en'),
      supportedLocales: kSupportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Directionality(
        textDirection: direction,
        child: Scaffold(body: child),
      ),
    );

WizardStep _step(String name) => WizardStep(
      title: name,
      subtitle: name,
      builder: (context, onNext) => Text('$name-body'),
    );

void main() {
  testWidgets('the wizard progress row mirrors its gaps in RTL',
      (tester) async {
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(_host(
        direction,
        StepWizard(
          isBusy: false,
          onComplete: () async {},
          steps: [_step('one'), _step('two'), _step('three')],
        ),
      ));
      await tester.pump(const Duration(seconds: 1));

      // Every horizontally-margined Container on the wizard chrome; in
      // practice that is the progress row's bars.
      final margins = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.margin)
          .whereType<EdgeInsetsGeometry>()
          .map((m) => m.resolve(direction))
          .where((e) => e.left > 0 || e.right > 0)
          .toList();

      expect(margins, isNotEmpty, reason: 'the progress bars should be spaced');
      for (final m in margins) {
        if (direction == TextDirection.ltr) {
          expect(m.right, greaterThan(0));
          expect(m.left, 0);
        } else {
          expect(m.left, greaterThan(0),
              reason: 'RTL: the gap must move to the left, or the progress row '
                  'reads back-to-front in Arabic and Urdu');
          expect(m.right, 0);
        }
      }
    }
  });

  testWidgets('AppInput insets its trailing affordance directionally',
      (tester) async {
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(_host(
        direction,
        AppInput(
          label: 'Email',
          controller: TextEditingController(),
          suffix: const Icon(Icons.check),
        ),
      ));
      await tester.pump();

      final insets = tester
          .widgetList<Padding>(find.descendant(
            of: find.byType(AppInput),
            matching: find.byType(Padding),
          ))
          .map((p) => p.padding.resolve(direction))
          .where((e) => e.left > 0 || e.right > 0)
          .toList();

      expect(insets, isNotEmpty, reason: 'the suffix should be inset');
      for (final e in insets) {
        if (direction == TextDirection.ltr) {
          expect(e.right, greaterThan(0));
        } else {
          expect(e.left, greaterThan(0),
              reason: 'RTL: the suffix inset must follow the trailing edge');
        }
      }
    }
  });
}
