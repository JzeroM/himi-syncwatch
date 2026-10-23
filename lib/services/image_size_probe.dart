import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class ImageSize {
  const ImageSize(this.width, this.height);

  final int width;
  final int height;
}

typedef ImageBytesFetcher = Future<Uint8List?> Function(
  Uri uri,
  Map<String, String> headers,
);

class ImageSizeProbe {
  ImageSizeProbe({
    ImageBytesFetcher? fetcher,
    this.maxBytes = 128 * 1024,
    this.timeout = const Duration(seconds: 3),
  }) : _fetcher = fetcher ?? _fetchBytes;

  final ImageBytesFetcher _fetcher;
  final int maxBytes;
  final Duration timeout;

  final Map<String, _ProbeCacheEntry> _cache = {};
  final Map<String, Future<ImageSize?>> _inflight = {};

  Future<ImageSize?> probe(String url, {String? accessToken}) {
    if (url.isEmpty) return Future.value();
    final key = '$url|${accessToken ?? ""}';
    final cached = _cache[key];
    if (cached != null && !cached.expired) return Future.value(cached.size);
    final pending = _inflight[key];
    if (pending != null) return pending;

    final headers = <String, String>{
      if (accessToken != null && accessToken.isNotEmpty)
        'X-Emby-Token': accessToken,
    };
    final future = _fetchBytesFor(Uri.parse(url), headers)
        .then<ImageSize?>(
            (bytes) => bytes == null ? null : parseImageSize(bytes))
        .then<ImageSize?>((size) {
      _cache[key] = _ProbeCacheEntry(
        size,
        size == null ? const Duration(minutes: 5) : const Duration(hours: 24),
      );
      return size;
    }).whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = future;
    return future;
  }

  Future<Uint8List?> _fetchBytesFor(
    Uri uri,
    Map<String, String> headers,
  ) async {
    try {
      return await _fetcher(uri, headers).timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _fetchBytes(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3)
      ..badCertificateCallback = (_, __, ___) => true;
    try {
      final request = await client.getUrl(uri);
      headers.forEach(request.headers.set);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-131071');
      final response = await request.close();
      if (response.statusCode >= 400) return null;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length >= 128 * 1024) break;
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  static ImageSize? parseImageSize(Uint8List bytes) {
    if (_isPng(bytes)) return _parsePng(bytes);
    if (_isJpeg(bytes)) return _parseJpeg(bytes);
    if (_isWebp(bytes)) return _parseWebp(bytes);
    return null;
  }

  static bool _isPng(Uint8List b) =>
      b.length >= 24 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47;

  static ImageSize? _parsePng(Uint8List b) {
    if (b.length < 24) return null;
    final width = _readUint32Be(b, 16);
    final height = _readUint32Be(b, 20);
    return width > 0 && height > 0 ? ImageSize(width, height) : null;
  }

  static bool _isJpeg(Uint8List b) =>
      b.length >= 4 && b[0] == 0xFF && b[1] == 0xD8;

  static ImageSize? _parseJpeg(Uint8List b) {
    var i = 2;
    while (i + 1 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      while (i < b.length && b[i] == 0xFF) {
        i++;
      }
      if (i >= b.length) break;
      final marker = b[i++];
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) break;
      if (i + 1 >= b.length) break;
      final segmentLength = (b[i] << 8) | b[i + 1];
      if (segmentLength < 2) break;
      if (_isJpegSof(marker)) {
        if (i + 6 >= b.length) break;
        final height = (b[i + 3] << 8) | b[i + 4];
        final width = (b[i + 5] << 8) | b[i + 6];
        return width > 0 && height > 0 ? ImageSize(width, height) : null;
      }
      i += segmentLength;
    }
    return null;
  }

  static bool _isJpegSof(int marker) =>
      marker >= 0xC0 &&
      marker <= 0xCF &&
      marker != 0xC4 &&
      marker != 0xC8 &&
      marker != 0xCC;

  static bool _isWebp(Uint8List b) =>
      b.length >= 30 &&
      b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50;

  static ImageSize? _parseWebp(Uint8List b) {
    if (b.length < 30) return null;
    final tag = String.fromCharCodes(b.sublist(12, 16));
    if (tag == 'VP8X') {
      final width = 1 + (b[24] | (b[25] << 8) | (b[26] << 16));
      final height = 1 + (b[27] | (b[28] << 8) | (b[29] << 16));
      return ImageSize(width, height);
    }
    if (tag == 'VP8L') {
      if (b.length < 25 || b[20] != 0x2F) return null;
      final b1 = b[21];
      final b2 = b[22];
      final b3 = b[23];
      final b4 = b[24];
      final width = 1 + (((b2 & 0x3F) << 8) | b1);
      final height = 1 + (((b4 & 0x0F) << 10) | (b3 << 2) | ((b2 & 0xC0) >> 6));
      return ImageSize(width, height);
    }
    if (tag == 'VP8 ') {
      if (b.length < 30 || b[23] != 0x9D || b[24] != 0x01 || b[25] != 0x2A) {
        return null;
      }
      final width = (b[26] | (b[27] << 8)) & 0x3FFF;
      final height = (b[28] | (b[29] << 8)) & 0x3FFF;
      return width > 0 && height > 0 ? ImageSize(width, height) : null;
    }
    return null;
  }

  static int _readUint32Be(Uint8List b, int offset) =>
      (b[offset] << 24) |
      (b[offset + 1] << 16) |
      (b[offset + 2] << 8) |
      b[offset + 3];
}

class _ProbeCacheEntry {
  _ProbeCacheEntry(this.size, Duration ttl)
      : expiresAt = DateTime.now().add(ttl);

  final ImageSize? size;
  final DateTime expiresAt;

  bool get expired => DateTime.now().isAfter(expiresAt);
}
