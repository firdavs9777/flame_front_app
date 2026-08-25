import 'package:flutter_test/flutter_test.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';

void main() {
  group('resumeStepFor', () {
    test('a draft with no password restores to step 0, whatever it saved', () {
      // The password is deliberately never persisted. Landing the user past
      // step 0 means register() posts '' and the server 422s on min(8) with
      // nothing on screen to explain it.
      expect(
        resumeStepFor(password: '', savedStep: 3, totalSteps: 5),
        0,
      );
    });

    test('a draft with a password honours its saved step', () {
      expect(
        resumeStepFor(password: 'hunter22', savedStep: 3, totalSteps: 5),
        3,
      );
    });

    test('clamps a saved step past the end of the flow', () {
      expect(
        resumeStepFor(password: 'hunter22', savedStep: 99, totalSteps: 5),
        4,
      );
    });

    test('clamps a negative saved step', () {
      expect(
        resumeStepFor(password: 'hunter22', savedStep: -2, totalSteps: 5),
        0,
      );
    });
  });
}
