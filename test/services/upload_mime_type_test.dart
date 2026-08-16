import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flame/services/api_client.dart';

// uploadFile sends through MultipartRequest.send(), which builds its own
// client, so the injected one is never consulted for an upload — the content
// type has to be asserted at its source.
class _UnusedClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async =>
      http.StreamedResponse(Stream.value(utf8.encode('{}')), 200, request: req);
}

void main() {
  // Three of the four upload routes rejected every real client request: this
  // map was written for photo upload and defaulted everything to image/jpeg,
  // so a .mp4 or .m4a arrived labelled as a JPEG and failed the backend's
  // per-kind allowlist (mediaService.LIMITS) with a 422. The backend's own
  // tests missed it because supertest sets the true content type.
  test('uploads are labelled with the content type each media route accepts',
      () {
    final client = ApiClient.testInstance(httpClient: _UnusedClient());

    String mime(String path) => client.mimeTypeForFile(path).mimeType;

    // video route: video/mp4 | video/quicktime
    expect(mime('/tmp/clip.mp4'), 'video/mp4');
    expect(mime('/tmp/clip.MOV'), 'video/quicktime');
    // audio + voice routes: audio/mpeg | audio/mp4 | audio/aac | audio/ogg
    expect(mime('/tmp/note.m4a'), 'audio/mp4');
    expect(mime('/tmp/song.mp3'), 'audio/mpeg');
    expect(mime('/tmp/clip.aac'), 'audio/aac');
    expect(mime('/tmp/clip.ogg'), 'audio/ogg');
    // image route: unchanged, plus jpg/jpeg now explicit rather than default
    expect(mime('/tmp/p.png'), 'image/png');
    expect(mime('/tmp/p.webp'), 'image/webp');
    expect(mime('/tmp/p.jpg'), 'image/jpeg');
    expect(mime('/tmp/p.jpeg'), 'image/jpeg');
    // .heic deliberately still falls through: image/heic is not on the
    // backend allowlist, and no picker in the app produces one (they all pass
    // imageQuality, which makes image_picker re-encode to JPEG).
    expect(mime('/tmp/p.heic'), 'image/jpeg');
  });
}
