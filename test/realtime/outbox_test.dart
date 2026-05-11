import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flame/realtime/outbox.dart';
import 'package:flame/realtime/outbox_entry.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('enqueue persists across reconstruction', () async {
    final box = OutboxRepo();
    await box.load();
    await box.enqueue(_entry('cmid-1', 'c1'));
    expect((box.all).length, 1);

    final box2 = OutboxRepo();
    await box2.load();
    expect(box2.all.length, 1);
    expect(box2.all.first.clientMessageId, 'cmid-1');
  });

  test('markSent removes entry', () async {
    final box = OutboxRepo();
    await box.load();
    await box.enqueue(_entry('cmid-1', 'c1'));
    await box.markSent('cmid-1', canonicalMessageId: 'srv-1');
    expect(box.all, isEmpty);
  });

  test('markFailed after max attempts', () async {
    final box = OutboxRepo();
    await box.load();
    await box.enqueue(_entry('cmid-1', 'c1'));
    for (var i = 0; i < 5; i++) {
      await box.bumpAttempt('cmid-1');
    }
    expect(box.all.first.status, OutboxStatus.failed);
  });
}

OutboxEntry _entry(String cmid, String cid) => OutboxEntry(
  clientMessageId: cmid, conversationId: cid, type: 'text',
  content: 'x', createdAt: DateTime(2026, 1, 1));
