import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart' as ohos_picker;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:himi_syncwatch/services/log_service.dart';

/// 用户选中的备份文件（已读出文本）。
class PickedBackupFile {
  const PickedBackupFile({required this.name, required this.text});

  /// 文件名（不含目录，仅用于提示）。
  final String name;

  /// 文件全文（JSON 文本，尚未校验）。
  final String text;
}

/// 备份文件的落盘 / 读取。
///
/// 各平台差异集中在这里（UI 层只管「给我内容 → 拿路径」）：
///
/// | 平台 | 保存 | 选择 |
/// |---|---|---|
/// | Windows / macOS / Linux | `saveFile` 返回路径，**由 Dart 写文件** | `pickFiles` 返回真实路径 |
/// | Android / iOS | `saveFile(bytes:)`，插件自己写 SAF/沙箱 | `pickFiles` 返回缓存副本路径 |
/// | 鸿蒙 | `saveFile(initialDirectory:)`，插件**复制已存在的文件** | `file_picker_ohos`（主包无 ohos 注册） |
///
/// 【鸿蒙为什么特殊】`file_picker_ohos` 原生侧 `saveFile` 把
/// `initialDirectory` 当作**源文件**（`fs.openSync(initialDirectory)` 后
/// `copyFileSync` 到用户选的位置），所以必须先写一份临时文件再把它的路径
/// 传进去；传目录或空值会直接报错。
class BackupFileIo {
  const BackupFileIo();

  /// 鸿蒙判定（主包 `file_picker` 没有 ohos 平台声明，`FilePicker.platform`
  /// 在鸿蒙上是 `LateInitializationError`）。
  bool get _isOhos => !kIsWeb && Platform.operatingSystem == 'ohos';

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 让用户选保存位置并写入 [content]；返回最终路径，用户取消返回 null。
  Future<String?> save({
    required String fileName,
    required String content,
  }) async {
    try {
      if (_isOhos) {
        // 鸿蒙原生侧把 `initialDirectory` 当**源文件**复制到用户选的位置，
        // 所以必须先写一份临时文件（不能传目录）。
        final tmpDir = await getTemporaryDirectory();
        final tmp = File('${tmpDir.path}/$fileName');
        await tmp.writeAsString(content, flush: true);
        return await ohos_picker.FilePicker.platform.saveFile(
          fileName: fileName,
          type: ohos_picker.FileType.custom,
          allowedExtensions: const ['json'],
          initialDirectory: tmp.path,
        );
      }
      if (_isMobile) {
        // 移动端插件要求直接给 bytes（它自己写进 SAF / 应用沙箱）。
        return await FilePicker.platform.saveFile(
          dialogTitle: '保存备份',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['json'],
          bytes: utf8.encode(content),
        );
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存备份',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (path == null || path.isEmpty) return null;
      final target = path.toLowerCase().endsWith('.json') ? path : '$path.json';
      await File(target).writeAsString(content, flush: true);
      return target;
    } catch (e, st) {
      LogService().log('Backup', '保存备份失败: $e\n$st');
      rethrow;
    }
  }

  /// 让用户选一个 JSON 备份文件并读出文本；取消返回 null。
  Future<PickedBackupFile?> pick() async {
    final path = await _pickPath();
    if (path == null || path.isEmpty) return null;
    try {
      final text = await File(path).readAsString();
      return PickedBackupFile(name: _basename(path), text: text);
    } catch (e, st) {
      LogService().log('Backup', '读取备份文件失败: $e\n$st');
      rethrow;
    }
  }

  Future<String?> _pickPath() async {
    if (_isOhos) {
      final result = await ohos_picker.FilePicker.platform.pickFiles(
        type: ohos_picker.FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return null;
      return result.files.first.path;
    }
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: '选择备份文件',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.first.path;
  }

  static String _basename(String path) {
    final idx = path.lastIndexOf(RegExp(r'[/\\]'));
    return idx < 0 ? path : path.substring(idx + 1);
  }
}
