import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';
import 'package:flame/services/user_service.dart';
import 'package:flame/providers/user_provider.dart';

class _FakeUserService extends UserService {
  String? deletedPassword;
  bool succeed = true;

  @override
  Future<ServiceResult<void>> deleteAccount({
    required String password,
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

    final ok = await n.deleteAccount(password: 'secret');

    expect(ok, isTrue);
    expect(fake.deletedPassword, 'secret');
    expect(n.state.value, isNull); // user cleared
  });

  test('deleteAccount failure returns false and keeps the user', () async {
    final fake = _FakeUserService()..succeed = false;
    final n = CurrentUserNotifier(fake)..setUser(_user());

    final ok = await n.deleteAccount(password: 'wrong');

    expect(ok, isFalse);
    expect(n.state.value, isNotNull); // user unchanged
  });
}
