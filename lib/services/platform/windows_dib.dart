import 'dart:typed_data';

import 'package:image/image.dart' as img;

Uint8List? buildDibFromPng(Uint8List pngBytes) {
  try {
    final decoded = img.decodePng(pngBytes);
    if (decoded == null) return null;
    final rgba = decoded.convert(format: img.Format.uint8, numChannels: 4);
    final width = rgba.width;
    final height = rgba.height;
    if (width <= 0 || height <= 0) return null;

    final pixelBytes = width * height * 4;
    final out = Uint8List(40 + pixelBytes);
    final header = ByteData.sublistView(out, 0, 40);
    header.setUint32(0, 40, Endian.little);
    header.setInt32(4, width, Endian.little);
    header.setInt32(8, height, Endian.little);
    header.setUint16(12, 1, Endian.little);
    header.setUint16(14, 32, Endian.little);
    header.setUint32(16, 0, Endian.little);
    header.setUint32(20, pixelBytes, Endian.little);

    var offset = 40;
    for (var y = height - 1; y >= 0; y--) {
      for (var x = 0; x < width; x++) {
        final pixel = rgba.getPixel(x, y);
        final alpha = pixel.a.toInt().clamp(0, 255);
        final inverse = 255 - alpha;
        out[offset++] = (pixel.b.toInt() * alpha + 255 * inverse) ~/ 255;
        out[offset++] = (pixel.g.toInt() * alpha + 255 * inverse) ~/ 255;
        out[offset++] = (pixel.r.toInt() * alpha + 255 * inverse) ~/ 255;
        out[offset++] = 255;
      }
    }
    return out;
  } catch (_) {
    return null;
  }
}
