import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:flame/core/image/photo_compressor.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('compressor_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Writes a solid-colour PNG of the given size and returns the file.
  Future<File> makeImage(int width, int height, String name) async {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(120, 80, 200));
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(img.encodePng(image));
    return file;
  }

  test('a landscape image over 800px is resized by width', () async {
    final source = await makeImage(1600, 900, 'wide.png');

    final out = await const PhotoCompressor()
        .compress(source, tempDir: tempDir.path, index: 0);

    final decoded = img.decodeImage(await out.readAsBytes())!;
    expect(decoded.width, kMaxPhotoDimension);
    expect(decoded.height, lessThan(kMaxPhotoDimension));
  });

  test('a portrait image over 800px is resized by height', () async {
    final source = await makeImage(900, 1600, 'tall.png');

    final out = await const PhotoCompressor()
        .compress(source, tempDir: tempDir.path, index: 1);

    final decoded = img.decodeImage(await out.readAsBytes())!;
    expect(decoded.height, kMaxPhotoDimension);
    expect(decoded.width, lessThan(kMaxPhotoDimension));
  });

  test('an image already under the cap keeps its dimensions', () async {
    final source = await makeImage(400, 300, 'small.png');

    final out = await const PhotoCompressor()
        .compress(source, tempDir: tempDir.path, index: 2);

    final decoded = img.decodeImage(await out.readAsBytes())!;
    expect(decoded.width, 400);
    expect(decoded.height, 300);
  });

  test('the output is written to an index-stable path inside tempDir', () async {
    final source = await makeImage(100, 100, 'x.png');

    final out = await const PhotoCompressor()
        .compress(source, tempDir: tempDir.path, index: 3);

    expect(out.path, '${tempDir.path}/compressed_3.jpg');
  });

  test('undecodable bytes fall back to the original file', () async {
    final broken = File('${tempDir.path}/broken.jpg');
    await broken.writeAsBytes([0, 1, 2, 3, 4]);

    final out = await const PhotoCompressor()
        .compress(broken, tempDir: tempDir.path, index: 4);

    expect(out.path, broken.path);
  });

  test('an unwritable tempDir falls back to the original rather than throwing',
      () async {
    final source = await makeImage(100, 100, 'y.png');

    final out = await const PhotoCompressor()
        .compress(source, tempDir: '/no/such/directory', index: 5);

    expect(out.path, source.path);
  });
}
