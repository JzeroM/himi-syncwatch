import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:himi_syncwatch/services/room/qr_image_decoder.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

String _validRoomCode() => 'HIMI:${base64Url.encode(utf8.encode(jsonEncode({
          'v': 1,
          'appId': 'a' * 32,
          'channel': 'himi_test',
          't': <dynamic>[],
        })))}';

/// 生成带 4 模块白边的 QR 图片（scale 放大，模拟截图）。
Uint8List _qrImage(String data, {bool jpeg = false}) {
  const scale = 6;
  const quiet = 4;
  final matrix = Encoder.encode(data, ErrorCorrectionLevel.m).matrix!;
  final side = (matrix.width + quiet * 2) * scale;
  final image = img.Image(width: side, height: side);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < matrix.height; y++) {
    for (var x = 0; x < matrix.width; x++) {
      if (matrix.get(x, y) != 1) continue;
      img.fillRect(
        image,
        x1: (x + quiet) * scale,
        y1: (y + quiet) * scale,
        x2: (x + quiet + 1) * scale - 1,
        y2: (y + quiet + 1) * scale - 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
  }
  return jpeg ? img.encodeJpg(image, quality: 90) : img.encodePng(image);
}

void main() {
  group('QrImageDecoder', () {
    test('PNG 截图中的房间码可解码', () {
      final code = _validRoomCode();
      expect(QrImageDecoder.decodeBytes(_qrImage(code)), code);
    });

    test('JPEG 图片中的房间码可解码', () {
      final code = _validRoomCode();
      expect(QrImageDecoder.decodeBytes(_qrImage(code, jpeg: true)), code);
    });

    test('从文件路径解码', () {
      final dir = Directory.systemTemp.createTempSync('himi_qr_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final code = _validRoomCode();
      final file = File('${dir.path}/room.png')
        ..writeAsBytesSync(_qrImage(code));

      expect(QrImageDecoder.decodeFile(file.path), code);
    });

    test('空白图片 / 损坏字节 / 不存在的文件返回 null', () {
      final blank = img.Image(width: 240, height: 240);
      img.fill(blank, color: img.ColorRgb8(255, 255, 255));

      expect(
        QrImageDecoder.decodeBytes(Uint8List.fromList(img.encodePng(blank))),
        isNull,
      );
      expect(
        QrImageDecoder.decodeBytes(Uint8List.fromList([1, 2, 3, 4, 5])),
        isNull,
      );
      expect(
        QrImageDecoder.decodeFile('/tmp/himi_no_such_qr_image.png'),
        isNull,
      );
    });

    test('大图降采样后仍可解码', () {
      final code = _validRoomCode();
      final source = img.decodeImage(_qrImage(code))!;
      final large = img.copyResize(source,
          width: 3000, height: 3000, interpolation: img.Interpolation.average);
      expect(
        QrImageDecoder.decodeBytes(Uint8List.fromList(img.encodePng(large))),
        code,
      );
    });
  });
}
