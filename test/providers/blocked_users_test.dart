import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flame/services/report_service.dart';
import 'package:flame/services/user_service.dart' show ServiceResult;
import 'package:flame/providers/blocked_users_provider.dart';

class _FakeReportService extends ReportService {
  bool getCalled = false;
  bool unblockCalled = false;
  String? unblockedId;
  bool getSucceeds = true;
  bool unblockSucceeds = true;
  List<BlockedUser> blocked = [];

  @override
  Future<ServiceResult<List<BlockedUser>>> getBlockedUsers() async {
    getCalled = true;
    return getSucceeds
        ? ServiceResult.success(blocked)
        : ServiceResult.failure('Failed to get blocked users');
  }

  @override
  Future<ServiceResult<void>> unblockUser(String userId) async {
    unblockCalled = true;
    unblockedId = userId;
    return unblockSucceeds
        ? ServiceResult.success(null)
        : ServiceResult.failure('Failed to unblock user');
  }
}

BlockedUser _user(String id, String name) => BlockedUser(
      id: id,
      name: name,
      blockedAt: DateTime(2026, 1, 1),
    );

void main() {
  test('load() maps getBlockedUsers() into state as data', () async {
    final fake = _FakeReportService()
      ..blocked = [_user('u1', 'Alice'), _user('u2', 'Bob')];
    final n = BlockedUsersNotifier(fake);

    await n.load();

    expect(fake.getCalled, isTrue);
    expect(n.state.value, hasLength(2));
    expect(n.state.value!.map((u) => u.id), containsAll(['u1', 'u2']));
  });

  test('load() failure surfaces an AsyncError and does not throw', () async {
    final fake = _FakeReportService()..getSucceeds = false;
    final n = BlockedUsersNotifier(fake);

    await n.load();

    expect(n.state, isA<AsyncError>());
    expect(n.state.valueOrNull, isNull);
  });

  test('unblock() success removes the user from state and returns true', () async {
    final fake = _FakeReportService()
      ..blocked = [_user('u1', 'Alice'), _user('u2', 'Bob')];
    final n = BlockedUsersNotifier(fake);
    await n.load();

    final ok = await n.unblock('u1');

    expect(ok, isTrue);
    expect(fake.unblockCalled, isTrue);
    expect(fake.unblockedId, 'u1');
    expect(n.state.value, hasLength(1));
    expect(n.state.value!.single.id, 'u2');
  });

  test('unblock() failure keeps the user in state and returns false', () async {
    final fake = _FakeReportService()
      ..blocked = [_user('u1', 'Alice')]
      ..unblockSucceeds = false;
    final n = BlockedUsersNotifier(fake);
    await n.load();

    final ok = await n.unblock('u1');

    expect(ok, isFalse);
    expect(fake.unblockCalled, isTrue);
    expect(n.state.value, hasLength(1));
    expect(n.state.value!.single.id, 'u1');
  });
}
