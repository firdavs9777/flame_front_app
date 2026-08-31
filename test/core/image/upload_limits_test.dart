import 'package:flutter_test/flutter_test.dart';
import 'package:flame/core/image/upload_limits.dart';

void main() {
  test('profile uploads are large enough for a 3x full-bleed card', () {
    // A card is roughly the screen width; the largest common phone is ~430pt,
    // which at 3x is 1290 physical pixels.
    expect(kProfilePhotoMaxEdge, greaterThanOrEqualTo(1290));
  });

  test('profile uploads stay within the server ceiling', () {
    // MAX_PHOTO_SIZE is 10MB; 1440px at q85 is far below it, but the constant
    // should not drift upward without someone noticing.
    expect(kProfilePhotoMaxEdge, lessThanOrEqualTo(2048));
  });

  test('profile uploads match the server full variant', () {
    // The server generates its `full` variant at 1440. Uploading less would
    // make it upscale; uploading much more is bytes nobody sees.
    expect(kProfilePhotoMaxEdge, 1440);
  });

  test('chat images are capped at all', () {
    expect(kChatImageMaxEdge, greaterThan(0));
    expect(kChatImageMaxEdge, lessThanOrEqualTo(kProfilePhotoMaxEdge));
  });

  test('quality is set once, not per call site', () {
    expect(kUploadQuality, inInclusiveRange(70, 90));
  });
}
