import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/platform/windows_dib.dart';
import 'package:image/image.dart' as img;

void main() {
  test('buildDibFromPng 生成 32 位 BGRA 自底向上 DIB', () {
    final source = img.Image(width: 2, height: 2, numChannels: 4);
    source.setPixelRgba(0, 0, 255, 0, 0, 255);
    source.setPixelRgba(1, 0, 0, 255, 0, 255);
    source.setPixelRgba(0, 1, 0, 0, 255, 255);
    source.setPixelRgba(1, 1, 0, 0, 0, 0);

    final dib = buildDibFromPng(Uint8List.fromList(img.encodePng(source)));

    expect(dib, isNotNull);
    final bytes = dib!;
    final header = ByteData.sublistView(bytes, 0, 40);
    expect(header.getUint32(0, Endian.little), 40);
    expect(header.getInt32(4, Endian.little), 2);
    expect(header.getInt32(8, Endian.little), 2);
    expect(header.getUint16(12, Endian.little), 1);
    expect(header.getUint16(14, Endian.little), 32);
    expect(header.getUint32(16, Endian.little), 0);
    expect(header.getUint32(20, Endian.little), 16);
    expect(bytes.length, 56);
    expect(bytes.sublist(40, 44), <int>[255, 0, 0, 255]);
    expect(bytes.sublist(44, 48), <int>[255, 255, 255, 255]);
    expect(bytes.sublist(48, 52), <int>[0, 0, 255, 255]);
    expect(bytes.sublist(52, 56), <int>[0, 255, 0, 255]);
  });

  test('buildDibFromPng 对非法 PNG 返回 null', () {
    expect(buildDibFromPng(Uint8List.fromList(<int>[1, 2, 3])), isNull);
  });
}
