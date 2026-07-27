import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/models/user.dart';
import 'registration_flow.dart';

/// Persists an in-progress registration to `shared_preferences` so a user who
/// backgrounds or drops out mid-signup can resume where they left off.
///
/// Only scalar fields plus local photo *file paths* are stored — never raw
/// image bytes, uploaded URLs, or the password (which is intentionally not
/// persisted for security).
class RegistrationDraft {
  static const String _key = 'registration_draft';

  const RegistrationDraft();

  /// Serializes [data] and [step] into a JSON-safe map.
  Map<String, dynamic> toJson(RegistrationData data, int step) {
    return {
      'email': data.email,
      'name': data.name,
      'age': data.age,
      'gender': data.gender.name,
      'lookingFor': data.lookingFor.name,
      'bio': data.bio,
      'interests': data.interests,
      'latitude': data.latitude,
      'longitude': data.longitude,
      'photoFilePaths': data.photoFiles.map((f) => f.path).toList(),
      'step': step,
    };
  }

  /// Reconstructs [RegistrationData] from a stored [json] map. Photo files are
  /// rehydrated only from paths that still exist on disk; missing paths are
  /// silently dropped.
  RegistrationData fromJson(Map<String, dynamic> json) {
    final data = RegistrationData()
      ..email = (json['email'] as String?) ?? ''
      ..name = (json['name'] as String?) ?? ''
      ..age = (json['age'] as int?) ?? 18
      ..gender = _genderFrom(json['gender'] as String?)
      ..lookingFor = _genderFrom(json['lookingFor'] as String?)
      ..bio = (json['bio'] as String?) ?? ''
      ..interests = ((json['interests'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList()
      ..latitude = (json['latitude'] as num?)?.toDouble()
      ..longitude = (json['longitude'] as num?)?.toDouble();

    final paths = ((json['photoFilePaths'] as List?) ?? const [])
        .map((e) => e.toString());
    data.photoFiles = [
      for (final p in paths)
        if (File(p).existsSync()) File(p),
    ];

    return data;
  }

  /// Saves [data] at [step] under [_key]. Best-effort — callers may treat
  /// failures as non-fatal.
  Future<void> save(RegistrationData data, int step) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(toJson(data, step)));
  }

  /// Loads a saved draft, or null when none exists / it can't be parsed.
  Future<({RegistrationData data, int step})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final data = fromJson(json);
      final step = (json['step'] as int?) ?? 0;
      return (data: data, step: step);
    } catch (_) {
      return null;
    }
  }

  /// Removes any saved draft.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Gender _genderFrom(String? name) {
    if (name == null) return Gender.other;
    for (final g in Gender.values) {
      if (g.name == name) return g;
    }
    return Gender.other;
  }
}
