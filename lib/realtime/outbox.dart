import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'outbox_entry.dart';

const _kKey = 'realtime_outbox_v1';
const int kMaxAttempts = 5;

class OutboxRepo {
  final List<OutboxEntry> _entries = [];
  late SharedPreferences _prefs;

  List<OutboxEntry> get all => List.unmodifiable(_entries);

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString(_kKey);
    if (raw == null) return;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    _entries
      ..clear()
      ..addAll(list.map(OutboxEntry.fromJson));
  }

  Future<void> _persist() async {
    await _prefs.setString(_kKey, jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }

  Future<void> enqueue(OutboxEntry entry) async {
    _entries.add(entry);
    await _persist();
  }

  Future<void> markSending(String cmid) async {
    final i = _entries.indexWhere((e) => e.clientMessageId == cmid);
    if (i == -1) return;
    _entries[i] = _entries[i].copy(status: OutboxStatus.sending);
    await _persist();
  }

  Future<void> markSent(String cmid, {required String canonicalMessageId}) async {
    _entries.removeWhere((e) => e.clientMessageId == cmid);
    await _persist();
  }

  Future<void> bumpAttempt(String cmid, {String? errorCode}) async {
    final i = _entries.indexWhere((e) => e.clientMessageId == cmid);
    if (i == -1) return;
    final attempts = _entries[i].attempts + 1;
    final status = attempts >= kMaxAttempts ? OutboxStatus.failed : OutboxStatus.pending;
    _entries[i] = _entries[i].copy(status: status, attempts: attempts, errorCode: errorCode);
    await _persist();
  }

  Future<void> markFailedTerminal(String cmid, {required String errorCode}) async {
    final i = _entries.indexWhere((e) => e.clientMessageId == cmid);
    if (i == -1) return;
    _entries[i] = _entries[i].copy(status: OutboxStatus.failed, errorCode: errorCode);
    await _persist();
  }

  Future<void> resetSendingToPending() async {
    var changed = false;
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].status == OutboxStatus.sending) {
        _entries[i] = _entries[i].copy(status: OutboxStatus.pending);
        changed = true;
      }
    }
    if (changed) await _persist();
  }
}
