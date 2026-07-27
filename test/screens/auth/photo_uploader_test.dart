import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/screens/auth/registration/photo_uploader.dart';

void main() {
  const uploader = PhotoUploader();

  test('all succeed: returns URLs in order, index 0 flagged primary', () async {
    final files = [File('a.jpg'), File('b.jpg'), File('c.jpg')];
    final primaryFlags = <String, bool>{};

    final urls = await uploader.upload(
      files,
      uploadOne: (file, {required bool isPrimary}) async {
        primaryFlags[file.path] = isPrimary;
        return UploadOutcome(success: true, url: 'url://${file.path}');
      },
    );

    expect(urls, ['url://a.jpg', 'url://b.jpg', 'url://c.jpg']);
    expect(primaryFlags['a.jpg'], true);
    expect(primaryFlags['b.jpg'], false);
    expect(primaryFlags['c.jpg'], false);
  });

  test('middle file fails once then succeeds on retry: 3 URLs in order',
      () async {
    final files = [File('a.jpg'), File('b.jpg'), File('c.jpg')];
    final attempts = <String, int>{};

    final urls = await uploader.upload(
      files,
      uploadOne: (file, {required bool isPrimary}) async {
        final n = (attempts[file.path] ?? 0) + 1;
        attempts[file.path] = n;
        // 'b.jpg' fails on its first attempt, succeeds on retry.
        if (file.path == 'b.jpg' && n == 1) {
          return const UploadOutcome(success: false);
        }
        return UploadOutcome(success: true, url: 'url://${file.path}');
      },
    );

    expect(urls, ['url://a.jpg', 'url://b.jpg', 'url://c.jpg']);
    expect(attempts['b.jpg'], 2); // retried once
  });

  test('file fails twice: dropped, others preserved in order', () async {
    final files = [File('a.jpg'), File('b.jpg'), File('c.jpg')];
    final attempts = <String, int>{};

    final urls = await uploader.upload(
      files,
      uploadOne: (file, {required bool isPrimary}) async {
        attempts[file.path] = (attempts[file.path] ?? 0) + 1;
        if (file.path == 'b.jpg') {
          return const UploadOutcome(success: false);
        }
        return UploadOutcome(success: true, url: 'url://${file.path}');
      },
    );

    expect(urls, ['url://a.jpg', 'url://c.jpg']);
    expect(attempts['b.jpg'], 2); // attempted twice then dropped
  });

  test('empty list short-circuits to empty', () async {
    final urls = await uploader.upload(
      const [],
      uploadOne: (file, {required bool isPrimary}) async =>
          const UploadOutcome(success: true, url: 'x'),
    );
    expect(urls, isEmpty);
  });
}
