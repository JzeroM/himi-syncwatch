import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 652：deviceTypes 声明不一致导致 .app 无法安装。
///
/// 【真机问题】云调试 Mate 90 Pro（HarmonyOS 7.0.0.109）：
/// - `.hap` 能装
/// - `.app` 报「应用版本错误」
///
/// 【根因】两个包的 `deviceTypes` 不一致：
/// - `ohos/entry/src/main/module.json5` 原为 `["default", "tablet"]`
///   （缺 `phone`）→ hvigor 原生产出的 `.app` 带此值
/// - `ohos_pack.sh` 重打包 `.hap` 时强制改写为 `["phone"]`
/// - `.app` 走「跳过重打包」分支 → 保留 `["default","tablet"]`
///   → 云机（phone 类型）判定不适用 → 「应用版本错误」
///
/// 【修复】源头 `module.json5` 改为 `["phone", "tablet"]`，
/// 并让 `ohos_pack.sh` 用同一份 DEVICE_TYPES 常量。
void main() {
  String read(String p) => File(p).readAsStringSync();

  group('① module.json5 声明 phone', () {
    test('deviceTypes 含 phone 与 tablet', () {
      final src = read('ohos/entry/src/main/module.json5');
      expect(src, contains('"phone"'));
      expect(src, contains('"tablet"'));
      expect(
        src,
        isNot(contains('"default"')),
        reason: 'default 不是有效设备类型，会导致云机判定不适用',
      );
    });
  });

  group('② ohos_pack.sh 使用统一的 DEVICE_TYPES', () {
    late String src;

    setUp(() => src = read('scripts/ohos_pack.sh'));

    test('定义 DEVICE_TYPES 常量', () {
      expect(src, contains(r"DEVICE_TYPES = ['phone', 'tablet']"));
    });

    test('module.deviceTypes 用常量（不再硬编码 phone）', () {
      expect(src, contains("module['module']['deviceTypes'] = DEVICE_TYPES"));
      expect(
        src,
        isNot(contains("module['module']['deviceTypes'] = ['phone']")),
      );
    });

    test('pack.info 的 modules 与 packages 都用常量', () {
      final count = "item['deviceType'] = DEVICE_TYPES".allMatches(src).length;
      expect(count, 2, reason: 'modules 与 packages 各一处');
      expect(
        src,
        isNot(contains("item['deviceType'] = ['phone']")),
      );
    });
  });

  group('③ 版本号', () {
    test('pubspec 为 1.5.72+652', () {
      expect(read('pubspec.yaml'), contains('version: 1.5.72+652'));
    });
  });
}
