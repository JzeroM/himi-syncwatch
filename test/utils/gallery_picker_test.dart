import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 631：鸿蒙选图支持（`image_picker` 无鸿蒙实现 → 改走 `file_picker_ohos`）。
///
/// 单元测试无法真正拉起系统相册（需真机 + 平台通道），故这里做**源码级**
/// 契约校验，锁死三件事：
/// ① `GalleryPicker` 的平台分流正确（鸿蒙走 file_picker，其余走 image_picker）；
/// ② 三处调用点不再硬编码拦截鸿蒙；
/// ③ `GalleryImage` 的 path/name/isPng 语义正确。
void main() {
  final picker = File('lib/utils/gallery_picker.dart').readAsStringSync();
  final roomMenu =
      File('lib/widgets/room_menu_button.dart').readAsStringSync();
  final serverSheet = File(
    'lib/widgets/server_service_settings_sheet.dart',
  ).readAsStringSync();
  final scanner = File(
    'lib/screens/room/qr_scanner_screen.dart',
  ).readAsStringSync();

  String stripComments(String src) => src
      .split('\n')
      .map((line) {
        final i = line.indexOf('//');
        return i >= 0 ? line.substring(0, i) : line;
      })
      .join('\n');

  group('① GalleryPicker 平台分流', () {
    test('鸿蒙走 file_picker_ohos + FileType.image', () {
      // 必须直接 import file_picker_ohos（主包 file_picker 无 ohos 平台声明，
      // 其 dart_plugin_registrant 不会 registerWith → LateInitializationError）。
      expect(picker, contains("import 'package:file_picker_ohos/file_picker_ohos.dart'"));
      expect(picker, contains('FilePicker.platform.pickFiles'));
      expect(picker, contains('FileType.image'));
      expect(picker, contains("Platform.operatingSystem == 'ohos'"));
    });

    test('鸿蒙分支不得使用主包 file_picker（无 ohos 平台声明）', () {
      expect(
        picker,
        isNot(contains("import 'package:file_picker/file_picker.dart'")),
        reason: '主包 _instance 在鸿蒙是 late 未初始化 → LateInitializationError',
      );
    });

    test('非鸿蒙走 image_picker', () {
      expect(picker, contains('ImagePicker().pickImage'));
      expect(picker, contains('ImageSource.gallery'));
    });

    test('用户取消返回 null（两条分支都要有）', () {
      // image_picker 分支
      expect(picker, contains('if (picked == null) return null;'));
      // file_picker 分支
      expect(picker, contains('if (result == null || result.files.isEmpty)'));
    });

    test('鸿蒙分支必须判空 path（相册 URI 可能无本地路径）', () {
      expect(picker, contains('if (path == null || path.isEmpty) return null;'));
    });

    test('提供测试用平台覆盖点', () {
      expect(picker, contains('debugIsOhosOverride'));
    });
  });

  group('② GalleryImage 语义', () {
    test('持有 path + name', () {
      expect(picker, contains('final String path;'));
      expect(picker, contains('final String name;'));
    });

    test('readAsBytes 读本地文件', () {
      expect(picker, contains('File(path).readAsBytes()'));
    });

    test('isPng 同时看 name 与 path（鸿蒙缓存名可能被改写）', () {
      expect(picker, contains('bool get isPng'));
      expect(picker, contains("name.toLowerCase().endsWith('.png')"));
      expect(picker, contains("path.toLowerCase().endsWith('.png')"));
    });
  });

  group('③ 调用点不再拦截鸿蒙', () {
    test('房间码：不再有「鸿蒙暂不支持相册选图」', () {
      expect(stripComments(roomMenu), isNot(contains('鸿蒙暂不支持相册选图')));
    });

    test('房间码：走 GalleryPicker', () {
      expect(roomMenu, contains('GalleryPicker.pickImage'));
      expect(stripComments(roomMenu), isNot(contains('ImagePicker()')));
    });

    test('房间码：鸿蒙与 Windows 同走相册分支', () {
      // 统一用 GalleryPicker.isOhos（而非各自写 Platform.operatingSystem），
      // 这样测试可用 debugIsOhosOverride 覆盖。
      expect(roomMenu, contains('GalleryPicker.isOhos'));
      // 两者任一命中即 galleryOnly。
      expect(roomMenu, contains('galleryOnly'));
    });

    test('房间码：按钮文案/图标按平台自适应', () {
      expect(roomMenu, contains("'从相册选图'"));
      expect(roomMenu, contains("'扫码加入'"));
      expect(roomMenu, contains('Icons.image_outlined'));
      expect(roomMenu, contains('Icons.qr_code_scanner'));
    });

    test('头像：不再有「鸿蒙暂不支持选图上传头像」', () {
      expect(stripComments(serverSheet), isNot(contains('鸿蒙暂不支持选图上传头像')));
    });

    test('头像：走 GalleryPicker 并保留 512 缩放', () {
      expect(serverSheet, contains('GalleryPicker.pickImage(maxWidth: 512'));
      expect(stripComments(serverSheet), isNot(contains('ImagePicker()')));
    });

    test('头像：MIME 判断改用 GalleryImage.isPng', () {
      expect(serverSheet, contains('picked.isPng'));
    });

    test('相机扫码页：鸿蒙提示引导到「从相册选图」', () {
      expect(scanner, contains('鸿蒙暂不支持相机扫码'));
      expect(scanner, contains('从相册选图'));
    });
  });

  group('④ 已移除对 image_picker 的依赖（鸿蒙无实现）', () {
    test('room_menu_button 不再 import image_picker', () {
      expect(stripComments(roomMenu), isNot(contains('image_picker')));
    });

    test('server_service_settings_sheet 不再 import image_picker', () {
      expect(stripComments(serverSheet), isNot(contains('image_picker')));
    });
  });
}
