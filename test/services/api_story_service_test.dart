import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flame/services/api_client.dart';
import 'package:flame/services/story_service.dart';

/// Records every request so a test can assert the method and path the service
/// actually reached for, not just what it did with the reply.
class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.body, {this.status = 200});
  final String body;
  final int status;
  final List<String> calls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async {
    calls.add('${req.method} ${req.url.path}');
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      request: req,
    );
  }
}

({ApiStoryService service, _RecordingClient client}) _serviceReturning(
  String body, {
  int status = 200,
}) {
  final client = _RecordingClient(body, status: status);
  final service = ApiStoryService(
    client: ApiClient.testInstance(httpClient: client),
  );
  return (service: service, client: client);
}

String _storyJson(String id, {bool viewed = false}) {
  final created = DateTime.now().subtract(const Duration(hours: 1));
  return jsonEncode({
    'id': id,
    'user_id': 'author',
    'media_url': 'https://cdn/$id.jpg',
    'created_at': created.toIso8601String(),
    'expires_at': created.add(const Duration(hours: 24)).toIso8601String(),
    'view_count': 2,
    'has_viewed': viewed,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('feed', () {
    test('parses grouped authors from /stories/feed', () async {
      final t = _serviceReturning(
        '{"success":true,"data":{"users":['
        '{"user_id":"u1","name":"Mina","avatar_url":"a.jpg","stories":[${_storyJson('s1')}]}'
        ']}}',
      );

      final feed = await t.service.feed();

      expect(t.client.calls.single, endsWith('/stories/feed'));
      expect(feed.single.userId, 'u1');
      expect(feed.single.stories.single.id, 's1');
    });

    test('drops authors whose stories have all expired', () async {
      // The server filters on expiresAt, but a story can expire between the
      // query and the render. An author with nothing live must not leave an
      // empty ring in the tray.
      final old = DateTime.now().subtract(const Duration(hours: 30));
      final t = _serviceReturning(jsonEncode({
        'success': true,
        'data': {
          'users': [
            {
              'user_id': 'u1',
              'name': 'Mina',
              'avatar_url': '',
              'stories': [
                {
                  'id': 'gone',
                  'user_id': 'u1',
                  'media_url': 'x',
                  'created_at': old.toIso8601String(),
                  'expires_at': old.add(const Duration(hours: 24)).toIso8601String(),
                }
              ],
            }
          ]
        }
      }));

      expect(await t.service.feed(), isEmpty);
    });

    test('orders unviewed authors before seen ones', () async {
      final t = _serviceReturning(
        '{"success":true,"data":{"users":['
        '{"user_id":"seen","name":"S","avatar_url":"","stories":[${_storyJson('a', viewed: true)}]},'
        '{"user_id":"fresh","name":"F","avatar_url":"","stories":[${_storyJson('b')}]}'
        ']}}',
      );

      final feed = await t.service.feed();

      expect(feed.map((u) => u.userId).toList(), ['fresh', 'seen']);
    });

    test('returns empty rather than throwing when the request fails', () async {
      final t = _serviceReturning('{"error":{"message":"nope"}}', status: 500);
      expect(await t.service.feed(), isEmpty);
    });
  });

  group('myStories', () {
    test('parses the author group', () async {
      final t = _serviceReturning(
        '{"success":true,"data":'
        '{"user_id":"me","name":"Me","avatar_url":"","stories":[${_storyJson('s1')}]}}',
      );

      final mine = await t.service.myStories();

      expect(t.client.calls.single, endsWith('/stories/my'));
      expect(mine!.stories.single.id, 's1');
    });

    test('returns null when the server reports no active stories', () async {
      // ApiClient unwraps the envelope with `data?['data'] ?? data`, so a null
      // `data` falls back to the WHOLE body. Without handling that, "no
      // stories" arrives as a Map and parses into a story-less author group
      // that the tray would render as an empty ring.
      final t = _serviceReturning('{"success":true,"data":null}');
      expect(await t.service.myStories(), isNull);
    });
  });

  group('mutations', () {
    test('markViewed posts to the story view path', () async {
      final t = _serviceReturning('{"success":true,"data":{"view_count":3}}');
      await t.service.markViewed('s9');
      expect(t.client.calls.single, 'POST /flamebackend/v1/stories/s9/view');
    });

    test('delete calls DELETE on the story', () async {
      final t = _serviceReturning('{"success":true,"data":{"deleted":true}}');
      await t.service.delete('s9');
      expect(t.client.calls.single, 'DELETE /flamebackend/v1/stories/s9');
    });

    test('a failed markViewed does not throw into the viewer', () async {
      // The viewer fires this as the page turns; a dead network must not put a
      // red screen over the photo.
      final t = _serviceReturning('{"error":{"message":"nope"}}', status: 500);
      await expectLater(t.service.markViewed('s9'), completes);
    });
  });
}
