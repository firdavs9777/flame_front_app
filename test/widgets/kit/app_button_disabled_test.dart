import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flame/theme/app_theme.dart';
import 'package:flame/widgets/kit/kit.dart';

/// A disabled button must LOOK disabled, whichever way it was disabled.
///
/// App Review, Guideline 2.1(a): "The Skip for now button was unresponsive to
/// taps." It was a ghost button disabled by `onPressed: null` — and it
/// rendered in full accent colour, because the label colour was chosen from
/// the `isDisabled` FIELD rather than from whether the button actually
/// responds. A red, live-looking control that did nothing.
///
/// Primary and danger hid the same bug: their background greys out
/// independently, so they looked disabled anyway. Ghost has no background, so
/// there was nothing left to signal it.
Color _labelColour(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.color!;

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  for (final variant in AppButtonVariant.values) {
    group('${variant.name} variant', () {
      testWidgets('greys its label when disabled by a null callback',
          (tester) async {
        await tester.pumpWidget(_host(
          AppButton(text: 'Skip for now', variant: variant, onPressed: null),
        ));

        expect(_labelColour(tester, 'Skip for now'), AppColors.gray500,
            reason: 'onPressed: null is the common way a button is disabled');
      });

      testWidgets('greys its label when disabled by the flag', (tester) async {
        await tester.pumpWidget(_host(
          AppButton(
            text: 'Skip for now',
            variant: variant,
            isDisabled: true,
            onPressed: () {},
          ),
        ));

        expect(_labelColour(tester, 'Skip for now'), AppColors.gray500);
      });

      testWidgets('keeps its active colour when it can actually be pressed',
          (tester) async {
        // The fix must not grey out working buttons.
        await tester.pumpWidget(_host(
          AppButton(text: 'Skip for now', variant: variant, onPressed: () {}),
        ));

        expect(_labelColour(tester, 'Skip for now'), isNot(AppColors.gray500));
      });
    });
  }

  testWidgets('a disabled ghost button is visibly different from a live one',
      (tester) async {
    // The specific regression: on ghost there is no background to fall back
    // on, so if the label does not change there is no signal at all.
    await tester.pumpWidget(_host(
      Column(children: const [
        AppButton(
          key: Key('live'),
          text: 'Live',
          variant: AppButtonVariant.ghost,
          onPressed: _noop,
        ),
        AppButton(
          key: Key('dead'),
          text: 'Dead',
          variant: AppButtonVariant.ghost,
          onPressed: null,
        ),
      ]),
    ));

    expect(_labelColour(tester, 'Live'),
        isNot(_labelColour(tester, 'Dead')));
  });
}

void _noop() {}
