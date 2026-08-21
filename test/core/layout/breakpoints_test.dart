import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/layout/breakpoints.dart';

Future<WindowClass> classAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  late WindowClass seen;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      seen = windowClassOf(context);
      return const SizedBox();
    }),
  ));
  return seen;
}

void main() {
  testWidgets('a phone is compact', (tester) async {
    expect(await classAt(tester, const Size(390, 844)), WindowClass.compact);
  });

  testWidgets('599 is still compact and 600 is expanded', (tester) async {
    expect(await classAt(tester, const Size(599, 900)), WindowClass.compact);
    expect(await classAt(tester, const Size(600, 900)), WindowClass.expanded);
  });

  testWidgets('a tablet is expanded', (tester) async {
    expect(await classAt(tester, const Size(834, 1112)), WindowClass.expanded);
  });

  testWidgets('isCompact agrees with windowClassOf', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late bool compact;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        compact = isCompact(context);
        return const SizedBox();
      }),
    ));
    expect(compact, isTrue);
  });

  test('the deck is narrower than the sheet', () {
    // Both exist so a tablet gets a phone-sized deck and readable form rows,
    // which only works if the deck is the tighter of the two.
    expect(kDeckMaxWidth, lessThan(kSheetMaxWidth));
    expect(kExpandedBreakpoint, 600);
  });
}
