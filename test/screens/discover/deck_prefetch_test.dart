import 'package:flutter_test/flutter_test.dart';
import 'package:flame/models/user.dart';
import 'package:flame/screens/discover/deck_prefetch.dart';

User _user(String id) => User.fromJson({
      'id': id,
      'name': 'U$id',
      'photos': [
        {'id': 'p$id', 'url': 'https://cdn/$id.jpg'}
      ],
    });

void main() {
  group('urlsToPrefetch', () {
    test('takes the primary photo of the next two cards', () {
      final deck = [_user('1'), _user('2'), _user('3'), _user('4')];
      expect(
        urlsToPrefetch(deck, currentIndex: 0),
        ['https://cdn/2.jpg', 'https://cdn/3.jpg'],
      );
    });

    test('stops cleanly at the end of the deck', () {
      final deck = [_user('1'), _user('2')];
      expect(urlsToPrefetch(deck, currentIndex: 1), isEmpty);
    });

    test('skips cards with no photos', () {
      final deck = [
        _user('1'),
        User.fromJson({'id': '2', 'name': 'U2', 'photos': <dynamic>[]}),
        _user('3'),
      ];
      expect(urlsToPrefetch(deck, currentIndex: 0), ['https://cdn/3.jpg']);
    });

    test('handles an empty deck', () {
      expect(urlsToPrefetch(const <User>[], currentIndex: 0), isEmpty);
    });

    test('handles an index past the end', () {
      final deck = [_user('1')];
      expect(urlsToPrefetch(deck, currentIndex: 99), isEmpty);
    });

    test('prefers the full variant, since a card is full-bleed', () {
      final deck = [
        _user('1'),
        User.fromJson({
          'id': '2',
          'name': 'U2',
          'photos': [
            {
              'id': 'p2',
              'url': 'https://cdn/full.jpg',
              'url_thumb': 'https://cdn/thumb.webp',
            }
          ],
        }),
      ];
      expect(urlsToPrefetch(deck, currentIndex: 0), ['https://cdn/full.jpg']);
    });
  });
}
