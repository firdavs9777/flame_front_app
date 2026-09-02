import 'package:flutter_test/flutter_test.dart';

import 'package:flame/models/user.dart';

Map<String, dynamic> _json(Map<String, dynamic> extra) => {
      'id': 'u1',
      'name': 'Alex',
      'age': 28,
      'photos': <dynamic>[],
      ...extra,
    };

void main() {
  test('parses both language lists', () {
    final user = User.fromJson(_json({
      'languages_spoken': ['ko', 'en'],
      'languages_learning': ['es'],
    }));

    expect(user.languagesSpoken, ['ko', 'en']);
    expect(user.languagesLearning, ['es']);
  });

  test('absent fields read as empty, not null', () {
    // Every existing account, and every response from a server that has not
    // deployed yet. Empty means UNKNOWN everywhere downstream.
    final user = User.fromJson(_json({}));

    expect(user.languagesSpoken, isEmpty);
    expect(user.languagesLearning, isEmpty);
  });

  test('a null list reads as empty rather than throwing', () {
    final user = User.fromJson(_json({
      'languages_spoken': null,
      'languages_learning': null,
    }));

    expect(user.languagesSpoken, isEmpty);
    expect(user.languagesLearning, isEmpty);
  });

  test('copyWith carries the lists through', () {
    final user = User.fromJson(_json({'languages_spoken': ['ko']}));
    final copy = user.copyWith(languagesLearning: ['ja']);

    expect(copy.languagesSpoken, ['ko'], reason: 'untouched fields survive');
    expect(copy.languagesLearning, ['ja']);
  });

  test('parses the camelCase spelling the /auth/* responses emit', () {
    // authService.toPublic emits camelCase while /users/me and /discover
    // emit snake_case. Reading only one side left the in-memory user with
    // empty lists straight after login, which silently disabled chat
    // auto-translation until something refetched /users/me.
    final user = User.fromJson(_json({
      'languagesSpoken': ['ko', 'en'],
      'languagesLearning': ['es'],
    }));

    expect(user.languagesSpoken, ['ko', 'en']);
    expect(user.languagesLearning, ['es']);
  });

  test('snake_case wins when a payload carries both spellings', () {
    final user = User.fromJson(_json({
      'languages_spoken': ['ko'],
      'languagesSpoken': ['ja'],
      'languages_learning': ['es'],
      'languagesLearning': ['fr'],
    }));

    expect(user.languagesSpoken, ['ko']);
    expect(user.languagesLearning, ['es']);
  });

  test('a payload carrying neither spelling reads as empty', () {
    final user = User.fromJson(_json({'name': 'Alex'}));

    expect(user.languagesSpoken, isEmpty);
    expect(user.languagesLearning, isEmpty);
  });

}
