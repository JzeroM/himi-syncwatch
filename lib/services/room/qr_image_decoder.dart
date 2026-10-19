import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// 从图片文件解码二维码（Windows 无相机时的「扫码加入」实现）。
///
/// 仅解码 QR；图片损坏或找不到二维码返回 null。解码内容可能含房间凭证，
/// 禁止打印到日志。
class QrImageDecoder {
  QrImageDecoder._();

  /// 单边最大 2000px：手机原图通常 4000px+，先降采样可显著提速，
  /// 对二维码识别率影响很小。
  static const int _maxSide = 2000;

  static String? decodeFile(String path) {
    final Uint8List bytes;
    try {
      bytes = File(path).readAsBytesSync();
    } catch (_) {
      return null;
    }
    return decodeBytes(bytes);
  }

  static String? decodeBytes(Uint8List bytes) {
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      // 损坏/不支持的文件格式（解码器可能抛异常而非返回 null）
      return null;
    }
    if (decoded == null) return null;

    final image = _limitSize(img.bakeOrientation(decoded));
    final pixels = image
        .convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.abgr)
        .buffer
        .asInt32List();

    // 截图/翻拍图用 Hybrid 更稳；失败再退回全局直方图（纯色背景截图）。
    for (final makeBinarizer in <Binarizer Function(LuminanceSource)>[
      (source) => HybridBinarizer(source),
      (source) => GlobalHistogramBinarizer(source),
    ]) {
      try {
        final source = RGBLuminanceSource(image.width, image.height, pixels);
        final result =
            QRCodeReader().decode(BinaryBitmap(makeBinarizer(source)));
        return result.text;
      } catch (_) {
        // 换下一种二值化重试
      }
    }
    return null;
  }

  static img.Image _limitSize(img.Image image) {
    final longest = image.width > image.height ? image.width : image.height;
    if (longest <= _maxSide) return image;
    final scale = _maxSide / longest;
    return img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }
}
