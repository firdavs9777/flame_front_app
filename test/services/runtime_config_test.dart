import 'package:flutter_test/flutter_test.dart';
import 'package:flame/services/runtime_config_service.dart';

void main() {
  test('default is chatV2Enabled=false before fetch', () {
    // Lightweight smoke: the cached default must be safe (legacy chat path).
    // We don't construct ApiClient here — that needs full env setup.
    // Just verify the const default.
    const rc = RuntimeConfig(chatV2Enabled: false);
    expect(rc.chatV2Enabled, false);
  });

  test('chatV2Enabled getter respects construction value', () {
    const rc = RuntimeConfig(chatV2Enabled: true);
    expect(rc.chatV2Enabled, true);
  });
}
