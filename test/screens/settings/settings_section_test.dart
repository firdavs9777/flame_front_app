import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/layout/breakpoints.dart';
import 'package:flame/screens/settings/widgets/settings_section.dart';

Future<void> pump(WidgetTester tester, Widget child,
    {double textScale = 1.0, Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a section shows its title and children', (tester) async {
    await pump(tester, const SettingsSection(
      title: 'Account',
      children: [SettingsRow(title: 'Email')],
    ));

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
  });

  testWidgets('a row with onTap is tappable and reports it', (tester) async {
    var taps = 0;
    await pump(tester, SettingsSection(
      title: 'Account',
      children: [SettingsRow(title: 'Email', onTap: () => taps++)],
    ));

    await tester.tap(find.text('Email'));
    expect(taps, 1);
  });

  testWidgets('a row without onTap builds no InkWell', (tester) async {
    await pump(tester, const SettingsSection(
      title: 'Account',
      children: [SettingsRow(title: 'Email')],
    ));

    // A row that looks tappable but is not is the same class of lie as a dead
    // button, so InkWell must be absent rather than present-with-null.
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('a long title wraps at 2x text scale without overflow',
      (tester) async {
    await pump(tester, const SettingsSection(
      title: 'Privacy',
      children: [
        SettingsRow(
          title: 'Show my approximate distance to other people nearby',
          subtitle: 'Others can see roughly how far away you are',
          trailing: Icon(Icons.chevron_right),
        ),
      ],
    ), textScale: 2.0);

    expect(tester.takeException(), isNull);
  });

  testWidgets('rows are constrained on a wide window', (tester) async {
    await pump(tester, const SettingsSection(
      title: 'Account',
      children: [SettingsRow(key: ValueKey('row'), title: 'Email')],
    ), size: const Size(1200, 900));

    expect(tester.getSize(find.byKey(const ValueKey('row'))).width,
        lessThanOrEqualTo(kSheetMaxWidth));
  });
}
