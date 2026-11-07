import 'dart:io';

import 'package:file_picker_ohos/file_picker_ohos.dart' as ohos_picker;
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// 相册选图结果（跨平台统一形态）。
class GalleryImage {
  const GalleryImage({required this.path, required this.name});

  /// 本地真实文件路径（可直接 `File(path)` 读取）。
  final String path;

  /// 原文件名（含扩展名，用于 MIME 判断）。
  final String name;

  Future<Uint8List> readAsBytes() => File(path).readAsBytes();

  /// 是否 PNG（按扩展名判断，兼容鸿蒙缓存文件名被改写的情况）。
  bool get isPng {
    if (name.toLowerCase().endsWith('.png')) return true;
    return path.toLowerCase().endsWith('.png');
  }
}

/// 跨平台相册选图。
///
/// 平台差异（实测，勿凭直觉改）：
/// - Android / iOS / Windows：`image_picker` 有原生实现，直接可用。
/// - **鸿蒙：`image_picker` 无鸿蒙实现**（`ohos/entry/oh_modules/` 里没有
///   该插件），调用会抛 `MissingPluginException`。
///
/// 鸿蒙为什么**直接 import `file_picker_ohos`** 而不是主包 `file_picker`：
/// - 主包 `file_picker` 的 pubspec **没有 ohos 平台声明**，因此
///   `dart_plugin_registrant.dart` 的 ohos 分支**不会**调用
///   `FilePickerIO.registerWith()`（实测该分支只有 PathProvider /
///   UrlLauncher）。主包 `_instance` 是 `late`，未赋值 → 调用即
///   `LateInitializationError`。
/// - `file_picker_ohos` 的 `_instance` 是**静态字段初始化**：
///   `static FilePicker _instance = FilePicker._setPlatform();`，
///   其中 ohos 分支直接返回 `FilePickerIO()`——**import 即自动就绪**，
///   无需任何 `registerWith()`。
/// - 两者底层是**同一个** MethodChannel
///   （`miguelruivo.flutter.plugins.filepicker`），而鸿蒙原生侧注册的
///   `FilePickerPlugin` 监听的正是该 channel，故链路完整。
///
/// 鸿蒙返回的 `path` 是真实文件：`file_picker_ohos` 原生侧
/// `FileUtils.openFileStream` 会把相册 URI 复制到
/// `context.cacheDir/file_picker/`，因此可直接 `File(path).readAsBytes()`。
class GalleryPicker {
  GalleryPicker._();

  /// 鸿蒙平台判定（测试可覆盖）。
  @visibleForTesting
  static bool? debugIsOhosOverride;

  /// 当前是否鸿蒙（测试可用 [debugIsOhosOverride] 覆盖）。
  ///
  /// 对外暴露：调用方（如房间「加入」弹窗的按钮文案/分支）应统一用它，
  /// 避免各自写 `Platform.operatingSystem == 'ohos'` 导致测试无法覆盖。
  static bool get isOhos =>
      debugIsOhosOverride ??
      (!kIsWeb && Platform.operatingSystem == 'ohos');

  /// 打开相册选一张图片；用户取消返回 null。
  ///
  /// [maxWidth] / [maxHeight] 仅对 `image_picker` 生效（鸿蒙走
  /// `file_picker_ohos`，不提供缩放参数）。
  static Future<GalleryImage?> pickImage({
    int? maxWidth,
    int? maxHeight,
  }) async {
    if (isOhos) {
      return _pickWithFilePickerOhos();
    }
    return _pickWithImagePicker(maxWidth: maxWidth, maxHeight: maxHeight);
  }

  static Future<GalleryImage?> _pickWithImagePicker({
    int? maxWidth,
    int? maxHeight,
  }) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: maxWidth?.toDouble(),
      maxHeight: maxHeight?.toDouble(),
    );
    if (picked == null) return null;
    return GalleryImage(path: picked.path, name: picked.name);
  }

  static Future<GalleryImage?> _pickWithFilePickerOhos() async {
    final result = await ohos_picker.FilePicker.platform.pickFiles(
      type: ohos_picker.FileType.image,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final path = file.path;
    // 相册 URI 理论上已被原生侧复制为真实文件；仍防御性判空。
    if (path == null || path.isEmpty) return null;
    return GalleryImage(path: path, name: file.name);
  }
}
