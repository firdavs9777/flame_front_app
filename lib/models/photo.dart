/// One profile photo and its sized variants.
///
/// [url] is the full-size image and is always present. [urlMedium] and
/// [urlThumb] are null for photos uploaded before the variant pipeline, and for
/// photos the backfill has not reached — callers must go through
/// `photoUrlFor` rather than reading a variant field directly.
class Photo {
  const Photo({
    required this.id,
    required this.url,
    this.urlMedium,
    this.urlThumb,
    this.isPrimary = false,
    this.order = 0,
  });

  final String id;
  final String url;
  final String? urlMedium;
  final String? urlThumb;
  final bool isPrimary;
  final int order;

  /// Parses an entry that may be an object or a bare URL string.
  ///
  /// Throws if there is no usable URL; use [tryFromJson] when that is possible.
  factory Photo.fromJson(dynamic raw) {
    final photo = tryFromJson(raw);
    if (photo == null) {
      throw ArgumentError('photo entry has no usable url: $raw');
    }
    return photo;
  }

  /// Null when [raw] carries no usable URL, so a malformed entry can be dropped
  /// rather than crashing a profile.
  static Photo? tryFromJson(dynamic raw) {
    if (raw is String) {
      return raw.isEmpty ? null : Photo(id: '', url: raw);
    }
    if (raw is! Map) return null;

    final url = raw['url']?.toString() ?? '';
    if (url.isEmpty) return null;

    /// The server always emits the variant keys, null when the photo predates
    /// them, so absent and empty must both read as "no variant".
    String? optional(String key) {
      final value = raw[key]?.toString();
      return (value == null || value.isEmpty) ? null : value;
    }

    return Photo(
      id: raw['id']?.toString() ?? '',
      url: url,
      urlMedium: optional('url_medium'),
      urlThumb: optional('url_thumb'),
      isPrimary: raw['is_primary'] == true,
      order: raw['order'] is int ? raw['order'] as int : 0,
    );
  }

  Photo copyWith({bool? isPrimary, int? order}) => Photo(
        id: id,
        url: url,
        urlMedium: urlMedium,
        urlThumb: urlThumb,
        isPrimary: isPrimary ?? this.isPrimary,
        order: order ?? this.order,
      );

  @override
  bool operator ==(Object other) =>
      other is Photo &&
      other.id == id &&
      other.url == url &&
      other.urlMedium == urlMedium &&
      other.urlThumb == urlThumb &&
      other.isPrimary == isPrimary &&
      other.order == order;

  @override
  int get hashCode =>
      Object.hash(id, url, urlMedium, urlThumb, isPrimary, order);

  @override
  String toString() => 'Photo($id, $url)';
}
