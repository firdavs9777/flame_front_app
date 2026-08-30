import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/providers/user_provider.dart';

class _FakeUserService extends UserService {
  String? deletedPassword;
  bool succeed = true;

  @override
  Future<ServiceResult<void>> deleteAccount({
    String? password,
    String? reason,
  }) async {
    deletedPassword = password;
    return succeed
        ? ServiceResult.success(null)
        : ServiceResult.failure('Wrong password');
  }
}

User _user() => User.fromJson({
      'id': 'u1', 'name': 'Ann', 'age': 27, 'bio': '',
      'interests': <dynamic>[], 'gender': 'female', 'photos': <dynamic>[],
    });

void main() {
  test('deleteAccount success calls service with password and clears user', () async {
    final fake = _FakeUserService();
    final n = CurrentUserNotifier(fake)..setUser(_user());

    final failure = await n.deleteAccount(password: 'secret');

    expect(failure, isNull, reason: 'null means it worked');
    expect(fake.deletedPassword, 'secret');
    expect(n.state.value, isNull); // user cleared
  });

  test('deleteAccount hands back the reason and keeps the user', () async {
    final fake = _FakeUserService()..succeed = false;
    final n = CurrentUserNotifier(fake)..setUser(_user());

    final failure = await n.deleteAccount(password: 'wrong');

    // Was a bare bool, so the dialog could only say "Could not delete account.
    // Check your password." — wrong advice for a social account, which has no
    // password, and it hid whatever the server actually said.
    expect(failure, isNotNull);
    expect(n.state.value, isNotNull); // user unchanged
  });
}
