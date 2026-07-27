import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/models/user.dart';
import 'package:flame/screens/auth/registration/registration_flow.dart';
import 'package:flame/screens/auth/registration/registration_draft.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const draft = RegistrationDraft();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('save -> load round-trips all scalar fields + step', () async {
    final data = RegistrationData()
      ..email = 'ada@example.com'
      ..name = 'Ada'
      ..age = 29
      ..gender = Gender.female
      ..lookingFor = Gender.nonBinary
      ..bio = 'hello world'
      ..interests = ['Music', 'Travel']
      ..latitude = 12.34
      ..longitude = -56.78;

    await draft.save(data, 3);

    final loaded = await draft.load();
    expect(loaded, isNotNull);
    expect(loaded!.step, 3);
    expect(loaded.data.email, 'ada@example.com');
    expect(loaded.data.name, 'Ada');
    expect(loaded.data.age, 29);
    expect(loaded.data.gender, Gender.female);
    expect(loaded.data.lookingFor, Gender.nonBinary);
    expect(loaded.data.bio, 'hello world');
    expect(loaded.data.interests, ['Music', 'Travel']);
    expect(loaded.data.latitude, 12.34);
    expect(loaded.data.longitude, -56.78);
  });

  test('the password is NEVER persisted (no plaintext leak)', () async {
    final data = RegistrationData()
      ..email = 'ada@example.com'
      ..password = 'SuperSecret123!'
      ..name = 'Ada';

    // The serialized map must not carry the password under any key.
    final json = draft.toJson(data, 1);
    expect(json.containsKey('password'), isFalse);
    expect(json.values.contains('SuperSecret123!'), isFalse);

    // And neither must the raw string written to shared_preferences.
    await draft.save(data, 1);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('registration_draft') ?? '';
    expect(raw.contains('SuperSecret123!'), isFalse);

    // A resumed draft therefore has no password (re-prompted at submit).
    final loaded = await draft.load();
    expect(loaded!.data.password, '');
  });

  test('clear() empties the draft', () async {
    await draft.save(RegistrationData()..email = 'x@y.com', 1);
    expect(await draft.load(), isNotNull);

    await draft.clear();
    expect(await draft.load(), isNull);
  });

  test('load() with no draft returns null', () async {
    expect(await draft.load(), isNull);
  });

  test('a non-existent photo path is dropped without throwing', () async {
    // Create one real temp file, and reference one missing path.
    final real = File('${Directory.systemTemp.path}/draft_real_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await real.writeAsBytes([1, 2, 3]);
    addTearDown(() {
      if (real.existsSync()) real.deleteSync();
    });

    final data = RegistrationData()
      ..email = 'p@example.com'
      ..photoFiles = [real, File('/no/such/path/missing.jpg')];

    await draft.save(data, 4);

    final loaded = await draft.load();
    expect(loaded, isNotNull);
    // Only the file that still exists on disk is rehydrated.
    expect(loaded!.data.photoFiles.length, 1);
    expect(loaded.data.photoFiles.single.path, real.path);
  });
}
