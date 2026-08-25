import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/theme/app_theme.dart';
import 'package:flame/screens/auth/widgets/auth_snackbar.dart';

void main() {
  Future<void> pumpAndShow(
    WidgetTester tester,
    AuthSnackBarType type,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () =>
                  showAuthSnackBar(context, message: 'hello', type: type),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
  }

  testWidgets('shows the message', (tester) async {
    await pumpAndShow(tester, AuthSnackBarType.info);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('error uses the theme error colour', (tester) async {
    await pumpAndShow(tester, AuthSnackBarType.error);
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, AppTheme.errorColor);
  });

  testWidgets('info leaves the background to the theme', (tester) async {
    await pumpAndShow(tester, AuthSnackBarType.info);
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.backgroundColor, isNull);
  });

  testWidgets('an unmounted context is a no-op, not a crash', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(
      () => showAuthSnackBar(captured, message: 'gone'),
      returnsNormally,
    );
  });
}
