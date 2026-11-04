import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:himi_syncwatch/services/log_service.dart';
import 'package:himi_syncwatch/services/platform/windows_clipboard_image.dart';

/// 图片导出结果。
enum QrExportResult {
  /// 成功保存/分享。
  ok,

  /// 用户取消（仅桌面「另存为」对话框）。
  cancelled,

  /// 当前平台不支持。
  unsupported,

  /// 失败（含异常信息）。
  failed,
}

/// 二维码（以及任何 PNG）保存到相册 / 分享的统一入口（590）。
///
/// 【为什么需要这一层】旧实现四处各自直写
/// `/storage/emulated/0/DCIM/Himi`：
/// - Android 10+ 分区存储直接拒绝（`PathAccessException: errno = 13`）；
/// - 鸿蒙被显式拦成「暂不支持」；
/// - iOS 写到应用私有 Documents（用户在相册里根本看不到）；
/// - Windows 分享分支与保存分支实现不一致。
///
/// 现在按平台分派到各端的正确实现：
///
/// | 平台 | 保存 | 分享 |
/// |---|---|---|
/// | Android | MediaStore（API 29+）/ 直写 DCIM（API ≤28） | share_plus |
/// | iOS | `PHPhotoLibrary`（相册写入） | share_plus |
/// | 鸿蒙 | `photoAccessHelper.createAsset` | 系统分享（share_plus） |
/// | Windows | FilePicker「另存为」 | 剪贴板 |
class QrExportService {
  QrExportService._();

  /// 原生相册保存通道（Android / iOS / 鸿蒙共用）。
  static const MethodChannel _channel =
      MethodChannel('himi/gallery_saver');

  /// 保存到系统相册。
  ///
  /// [fileName] 不含扩展名（内部补 `.png`）；[subDir] 为相册内子目录
  /// （Android 落到 `DCIM/<subDir>`）。
  static Future<QrExportResult> save(
    Uint8List bytes, {
    required String fileName,
    String subDir = 'Himi',
  }) async {
    try {
      if (Platform.isWindows) {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: '保存图片',
          fileName: '$fileName.png',
          type: FileType.custom,
          allowedExtensions: const ['png'],
        );
        if (path == null) return QrExportResult.cancelled;
        final target = path.toLowerCase().endsWith('.png') ? path : '$path.png';
        await File(target).writeAsBytes(bytes, flush: true);
        return QrExportResult.ok;
      }
      if (Platform.isMacOS || Platform.isLinux) {
        // 桌面 Linux/macOS：写「下载」目录（无相册概念）。
        final dir = await getDownloadsDirectory();
        if (dir == null) return QrExportResult.unsupported;
        await File('${dir.path}/$fileName.png')
            .writeAsBytes(bytes, flush: true);
        return QrExportResult.ok;
      }
      // Android / iOS / 鸿蒙：原生通道写入系统相册。
      final ok = await _channel.invokeMethod<bool>('saveImage', <String, Object>{
        'bytes': bytes,
        'fileName': fileName,
        'subDir': subDir,
      });
      return (ok ?? false) ? QrExportResult.ok : QrExportResult.failed;
    } on MissingPluginException {
      LogService().log('QrExport', '相册通道未注册（save）');
      return QrExportResult.unsupported;
    } catch (e) {
      LogService().log('QrExport', '保存失败: $e');
      return QrExportResult.failed;
    }
  }

  /// 分享图片。
  ///
  /// [text]/[subject] 为分享附带文案（Windows 剪贴板忽略）。
  static Future<QrExportResult> share(
    Uint8List bytes, {
    required String fileName,
    String? subject,
    String? text,
  }) async {
    try {
      if (Platform.isWindows) {
        // Windows：SharePlus 支持有限，复制到剪贴板更可靠（沿用既有实现）。
        final copied = await _copyPngToClipboard(bytes);
        return copied ? QrExportResult.ok : QrExportResult.failed;
      }
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName.png');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: subject,
          text: text,
        ),
      );
      return QrExportResult.ok;
    } catch (e) {
      LogService().log('QrExport', '分享失败: $e');
      return QrExportResult.failed;
    }
  }

  /// Windows：PNG 字节 → 剪贴板（复用既有 win32 DIB 实现）。
  static Future<bool> _copyPngToClipboard(Uint8List bytes) async {
    try {
      return await copyPngToClipboard(bytes);
    } catch (_) {
      return false;
    }
  }
}
