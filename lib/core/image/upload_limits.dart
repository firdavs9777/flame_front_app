/// Upload dimension caps, in logical pixels on the long edge.
///
/// One home for them, because they were previously repeated at four call sites
/// with three different answers — and one call site with no answer at all.

/// Profile photos.
///
/// 1440 rather than the previous 1024: a full-bleed deck card is roughly the
/// screen width, which on a large phone at 3x is ~1290 physical pixels, so 1024
/// was being upscaled on the surface that matters most. Matches the server's
/// `full` variant edge, so it neither upscales nor wastes bytes. The server
/// generates the smaller variants from this, so raising it costs one upload and
/// improves every derived size.
const int kProfilePhotoMaxEdge = 1440;

/// Chat image attachments.
///
/// Previously uncapped — `imageQuality: 85` alone still ships a 12MP camera
/// photo at 12MP. Smaller than a profile photo because a chat bubble draws at
/// `kChatMediaWidth` (240pt) and the image is only ever full-bleed in the media
/// viewer.
const int kChatImageMaxEdge = 1280;

/// JPEG quality for every pick. The server re-encodes to WebP anyway, so this
/// only governs what crosses the wire on upload.
const int kUploadQuality = 85;
