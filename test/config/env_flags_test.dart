import 'package:flutter_test/flutter_test.dart';
import 'package:flame/config/env.dart';

void main() {
  test('social login and forgot-password are OFF by default (MVP)', () {
    expect(EnvConfig.current.authSocialEnabled, isFalse);
    expect(EnvConfig.current.forgotPasswordEnabled, isFalse);
    expect(EnvConfig.current.chatEnabled, isFalse);
  });
}
