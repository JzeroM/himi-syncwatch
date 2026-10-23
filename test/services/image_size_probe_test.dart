import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/image_size_probe.dart';

Uint8List _png(int width, int height) {
  final bytes = Uint8List(24);
  bytes.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  bytes.setAll(12, [0x49, 0x48, 0x44, 0x52]);
  bytes.buffer.asByteData().setUint32(16, width);
  bytes.buffer.asByteData().setUint32(20, height);
  return bytes;
}

Uint8List _jpeg(int width, int height) {
  return Uint8List.fromList([
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    0x00,
    0x04,
    0x00,
    0x00,
    0xFF,
    0xC0,
    0x00,
    0x11,
    0x08,
    (height >> 8) & 0xFF,
    height & 0xFF,
    (width >> 8) & 0xFF,
    width & 0xFF,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ]);
}

Uint8List _webp(int width, int height) {
  final bytes = Uint8List(30);
  bytes.setAll(0, 'RIFF'.codeUnits);
  bytes.setAll(8, 'WEBP'.codeUnits);
  bytes.setAll(12, 'VP8X'.codeUnits);
  bytes[16] = 0x0A;
  final w = width - 1;
  final h = height - 1;
  bytes[24] = w & 0xFF;
  bytes[25] = (w >> 8) & 0xFF;
  bytes[26] = (w >> 16) & 0xFF;
  bytes[27] = h & 0xFF;
  bytes[28] = (h >> 8) & 0xFF;
  bytes[29] = (h >> 16) & 0xFF;
  return bytes;
}

void main() {
  test('解析 PNG/JPEG/WebP 宽高', () {
    expect(ImageSizeProbe.parseImageSize(_png(1920, 1080))!.width, 1920);
    expect(ImageSizeProbe.parseImageSize(_png(1920, 1080))!.height, 1080);
    expect(ImageSizeProbe.parseImageSize(_jpeg(3840, 2160))!.width, 3840);
    expect(ImageSizeProbe.parseImageSize(_jpeg(3840, 2160))!.height, 2160);
    expect(ImageSizeProbe.parseImageSize(_webp(2560, 1440))!.width, 2560);
    expect(ImageSizeProbe.parseImageSize(_webp(2560, 1440))!.height, 1440);
  });

  test('无法识别的数据返回 null', () {
    expect(
        ImageSizeProbe.parseImageSize(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('相同 URL 复用缓存，不重复请求', () async {
    var calls = 0;
    final probe = ImageSizeProbe(
      fetcher: (uri, headers) async {
        calls++;
        return _png(1920, 1080);
      },
    );
    await probe.probe('https://s1/backdrop');
    await probe.probe('https://s1/backdrop');
    expect(calls, 1);
  });
}
