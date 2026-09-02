import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flame/core/push/device_id.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('generates an id on first call and persists it', () async {
    final first = await DeviceId.get();

    expect(first, isNotEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DeviceId.storageKey), first);
  });

  test('returns the same id on every later call', () async {
    // The whole point: the backend upserts device tokens by this id, so an id
    // that changed per call would append a new token entry each time and the
    // user would get one push per historical token.
    final first = await DeviceId.get();
    final second = await DeviceId.get();

    expect(second, first);
  });

  test('reuses an id stored by a previous launch', () async {
    SharedPreferences.setMockInitialValues({
      DeviceId.storageKey: 'stored-device-id',
    });

    expect(await DeviceId.get(), 'stored-device-id');
  });

  test('replaces an empty stored value rather than returning it', () async {
    SharedPreferences.setMockInitialValues({DeviceId.storageKey: ''});

    final id = await DeviceId.get();

    expect(id, isNotEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DeviceId.storageKey), id);
  });
}
